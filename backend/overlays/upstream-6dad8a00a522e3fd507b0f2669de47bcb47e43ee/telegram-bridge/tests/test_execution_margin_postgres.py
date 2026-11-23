"""PostgreSQL-only concurrency proof for account-wide margin admission.

Set MIDAS_TEST_POSTGRES_URL to a disposable PostgreSQL test database. This test
never points itself at DATABASE_URL and never creates/drops a whole schema.
"""
import asyncio
import os
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.database import Base
from app.execution_control import reserve_execution
from app.models import ExecutionLedger, ExecutionPositionModification, PortfolioReservation

POSTGRES_URL = os.getenv("MIDAS_TEST_POSTGRES_URL")
pytestmark = pytest.mark.skipif(not POSTGRES_URL, reason="MIDAS_TEST_POSTGRES_URL not configured")


@pytest.mark.asyncio
async def test_postgres_advisory_lock_prevents_concurrent_margin_oversubscription():
    engine = create_async_engine(POSTGRES_URL)
    tables = [
        Base.metadata.tables["execution_ledger"],
        Base.metadata.tables["portfolio_reservations"],
        Base.metadata.tables["execution_position_modifications"],
    ]
    portfolio_key = f"margin-concurrency-test:{uuid.uuid4()}"
    factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with engine.begin() as connection:
            await connection.run_sync(lambda sync: Base.metadata.create_all(sync, tables=tables))

        async def attempt(request_id: str) -> bool:
            async with factory() as session:
                accepted = await reserve_execution(
                    session,
                    portfolio_key=portfolio_key,
                    request_id=request_id,
                    signal_id=request_id,
                    symbol="EURUSD" if request_id.endswith("a") else "XAUUSD",
                    direction="BUY",
                    risk_r=0.25,
                    volatility=0.2,
                    factors={},
                    free_margin=1000.0,
                    required_margin=450.0,
                    margin_snapshot_epoch=int(datetime.now(timezone.utc).timestamp()) + 1,
                    account_currency="USD",
                )
                if accepted:
                    await session.commit()
                else:
                    await session.rollback()
                return accepted

        accepted = await asyncio.gather(
            attempt(f"{portfolio_key}:a"),
            attempt(f"{portfolio_key}:b"),
        )
        assert sorted(accepted) == [False, True]
    finally:
        async with factory() as session:
            await session.execute(delete(PortfolioReservation).where(PortfolioReservation.portfolio_key == portfolio_key))
            await session.execute(delete(ExecutionLedger).where(ExecutionLedger.portfolio_key == portfolio_key))
            await session.execute(delete(ExecutionPositionModification).where(ExecutionPositionModification.portfolio_key == portfolio_key))
            await session.commit()
        await engine.dispose()
