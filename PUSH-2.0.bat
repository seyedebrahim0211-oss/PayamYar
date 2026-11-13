@echo off
cd /d "%~dp0"
git checkout claude/payamyar-2.0
git push -u origin claude/payamyar-2.0
echo.
echo Done. Open a pull request into main on GitHub to build the site, Bazaar and Myket APKs.
pause
