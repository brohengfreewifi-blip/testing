@echo off
setlocal
cd /d "%~dp0"
echo ==== V-RPGMaker IPA builder ====
echo iOS apps need macOS to compile, so this script builds on a free GitHub macOS runner.
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [X] Git is not installed. Get it from https://git-scm.com/
  pause
  exit /b 1
)
where gh >nul 2>nul
if errorlevel 1 (
  echo [X] GitHub CLI is not installed. Get it from https://cli.github.com/
  pause
  exit /b 1
)

gh auth status >nul 2>nul
if errorlevel 1 (
  echo Logging in to GitHub...
  gh auth login
  if errorlevel 1 (
    echo Login failed.
    pause
    exit /b 1
  )
)

if not exist ".git" (
  git init
  git branch -M main
)
git add -A
git commit -m "V-RPGMaker build" >nul 2>nul

git remote get-url origin >nul 2>nul
if errorlevel 1 (
  echo Creating private GitHub repo V-RPGMaker...
  gh repo create V-RPGMaker --private --source=. --remote=origin
  if errorlevel 1 (
    echo Could not create repo.
    pause
    exit /b 1
  )
)

echo Pushing...
git push -u origin main
if errorlevel 1 (
  echo Push failed.
  pause
  exit /b 1
)

echo Starting cloud build...
gh workflow run build-ipa.yml --ref main
if errorlevel 1 (
  echo Could not start workflow.
  pause
  exit /b 1
)

echo Waiting for the run to register...
timeout /t 15 /nobreak >nul

set RUNID=
for /f %%i in ('gh run list --workflow=build-ipa.yml --limit 1 --json databaseId --jq ".[0].databaseId"') do set RUNID=%%i
if "%RUNID%"=="" (
  echo Could not find the run.
  pause
  exit /b 1
)

echo Watching run %RUNID%. This takes about 5 to 10 minutes.
gh run watch %RUNID% --exit-status
if errorlevel 1 (
  echo Build failed. See the log with: gh run view %RUNID% --log-failed
  pause
  exit /b 1
)

if exist build rmdir /s /q build
gh run download %RUNID% -n V-RPGMaker-ipa -D build
if errorlevel 1 (
  echo Download failed.
  pause
  exit /b 1
)

echo.
echo ==== DONE ====
echo IPA saved to: %~dp0build\V-RPGMaker.ipa
echo The IPA is UNSIGNED. Install it with Sideloadly, AltStore, or TrollStore.
pause
