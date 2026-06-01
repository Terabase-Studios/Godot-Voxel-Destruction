@echo off
setlocal

if not exist "upscaled" mkdir "upscaled"

echo.
echo === Processing PNG files ===
echo.

for %%F in (*.png) do (
    echo Processing %%F...

    magick "%%F" ^
        -resize 1280x720 ^
        -background none ^
        -gravity center ^
        -extent 1280x720 ^
        "upscaled\upscaled_%%~nxF"
)

echo.
echo === Processing GIF files ===
echo.

for %%F in (*.gif) do (
    echo Processing %%F...

    magick "%%F" ^
        -coalesce ^
        -resize 1280x720 ^
        -background none ^
        -gravity center ^
        -extent 1280x720 ^
        -layers Optimize ^
        "upscaled\upscaled_%%~nxF"
)

echo.
echo Done!
pause