from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import status
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
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc


@router.post("/logout")
async def logout():
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
