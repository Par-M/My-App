from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.config import settings
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import DevLoginRequest
from app.schemas.auth import GoogleLoginRequest
from app.schemas.auth import RefreshRequest
from app.schemas.auth import TokenResponse
from app.schemas.auth import UserOut
from app.services.auth_service import AuthError
from app.services.auth_service import AuthService
from app.services.google import GoogleTokenVerificationError

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"],
)


@router.post(
    "/google",
    response_model=TokenResponse,
)
async def sign_in_with_google(
    request: GoogleLoginRequest,
    db: Session = Depends(get_db),
):
    service = AuthService(db)
    try:
        return service.login_with_google(request.id_token)
    except GoogleTokenVerificationError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid Google ID token: {exc}",
        ) from exc


@router.post(
    "/dev",
    response_model=TokenResponse,
)
async def sign_in_dev(
    request: DevLoginRequest,
    db: Session = Depends(get_db),
):
    if not settings.enable_dev_auth:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not found",
        )
    service = AuthService(db)
    return service.login_dev(request.name, request.email)


@router.post(
    "/refresh",
    response_model=TokenResponse,
)
async def refresh_token(
    request: RefreshRequest,
    db: Session = Depends(get_db),
):
    service = AuthService(db)
    try:
        return service.refresh(request.refresh_token)
    except (ValueError, AuthError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc


class LogoutRequest(BaseModel):
    refresh_token: str | None = None


@router.post("/logout")
async def logout(
    request: LogoutRequest | None = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke the caller's refresh sessions.

    Requires authentication. Previously this returned success without revoking
    anything, so a copied refresh token stayed valid until it expired.

    With a refresh token in the body only that session is revoked; without one
    every session for the user is revoked.
    """
    service = AuthService(db)
    try:
        service.logout(
            current_user,
            refresh_token=request.refresh_token if request else None,
        )
    except (ValueError, AuthError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc
    return {"message": "Logged out"}


@router.get(
    "/me",
    response_model=UserOut,
)
async def me(
    current_user: User = Depends(get_current_user),
):
    return UserOut(
        id=current_user.id,
        email=current_user.email,
        name=current_user.name,
        provider=current_user.provider,
    )
