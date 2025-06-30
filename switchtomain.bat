@echo off
REM This batch script automates switching to the 'main' branch and pulling the latest changes.

echo Checking out the 'main' branch...
git checkout main

REM Check if the checkout was successful
if %errorlevel% neq 0 (
    echo Error: Failed to checkout 'main' branch.
    goto :end
)

echo Pulling latest changes from 'origin/main'...
git pull origin main

REM Check if the pull was successful
if %errorlevel% neq 0 (
    echo Error: Failed to pull from 'origin/main'.
    goto :end
)

echo.
echo Git operations completed successfully for 'main' branch.

:end
pause
