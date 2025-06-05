@echo off
REM This script runs flutter clean and flutter pub get in the specified directory.

REM Set title for the CMD window
title VisionSpark Project Maintenance

REM Clear the screen
cls

REM --- ASCII Art Banner ---
color 0B 
REM Light Aqua on Black. Other options: 0A (Light Green), 0E (Light Yellow), 0F (Bright White)
echo  VVVVVVVV           VVVVVVVV IIIIIIIIII   SSSSSSSSSSSSSSS IIIIIIIIII     OOOOOOOOO     NNNNNNNN        NNNNNNNN
echo  V::::::V           V::::::V I::::::::I  SS:::::::::::::::SI::::::::I   OO:::::::::OO   N:::::::N       N::::::N
echo  V::::::V           V::::::V I::::::::I S:::::SSSSSS::::::SI::::::::I OO:::::::::::::OO N::::::::N      N::::::N
echo  V::::::V           V::::::V II::::::II S:::::S     SSSSSSSII::::::IIO:::::::OOO:::::::ON:::::::::N     N::::::N
echo   V:::::V           V:::::V    I::::I   S:::::S              I::::I  O::::::O   O::::::ON::::::::::N    N::::::N
echo    V:::::V         V:::::V     I::::I   S:::::S              I::::I  O:::::O     O:::::ON:::::::::::N   N::::::N
echo     V:::::V       V:::::V      I::::I    S::::SSSS           I::::I  O:::::O     O:::::ON:::::::N::::N  N::::::N
echo      V:::::V     V:::::V       I::::I     SS::::::SSSSS      I::::I  O:::::O     O:::::ON::::::N N::::N N::::::N
echo       V:::::V   V:::::V        I::::I       SSS::::::::SS    I::::I  O:::::O     O:::::ON::::::N  N::::N:::::::N
echo        V:::::V V:::::V         I::::I          SSSSSS::::S   I::::I  O:::::O     O:::::ON::::::N   N:::::::::::N
echo         V:::::V:::::V          I::::I               S:::::S  I::::I  O:::::O     O:::::ON::::::N    N::::::::::N
echo          V:::::::::V           I::::I               S:::::S  I::::I  O::::::O   O::::::ON::::::N     N:::::::::N
echo           V:::::::V          II::::::II SSSSSSS     S:::::SII::::::IIO:::::::OOO:::::::ON::::::N      N::::::::N
echo            V:::::V           I::::::::I S::::::SSSSSS:::::SI::::::::I OO:::::::::::::OO N::::::N       N:::::::N
echo             V:::V            I::::::::I S:::::::::::::::SS I::::::::I   OO:::::::::OO   N::::::N        N::::::N
echo              VVV             IIIIIIIIII  SSSSSSSSSSSSSSS   IIIIIIIIII     OOOOOOOOO     NNNNNNNN         NNNNNNN
echo.
echo                   PPPPPPPPPPRRRRRRRRRRRRRRRRR        OOOOOOOOO        JJJJJJJJJJJ EEEEEEEEEEEEEEEEEEEEEE CCCCCCCCCCCCC TTTTTTTTTTTTTTTTTTTTTTT
echo                   P::::::::PPR::::::::::::::::R     OO:::::::::OO      J::::::::J E::::::::::::::::::::E C::::::::::::CT:::::::::::::::::::::T
echo                   P::::::::PPR::::::RRRRRR:::::R  OO:::::::::::::OO    J::::::::J E::::::::::::::::::::EC:::::CCCCCCCCCT:::::::::::::::::::::T
echo                   PP:::::::PPRR:::::R     R:::::RO:::::::OOO:::::::O   J:::::::J  EE:::::EEEEEEEEEEC:::::C     CCCCCCCT:::::TT:::::TT:::::T
echo                     P::::P    R::::R     R:::::RO::::::O   O::::::O   J:::::::J    E:::::E          C:::::C              T:::::T  T:::::T  T:::::T
echo                     P::::P    R::::R     R:::::RO:::::O     O:::::O   J:::::::J    E:::::E          C:::::C              T:::::T  T:::::T  T:::::T
echo                     P::::P    R::::RRRRRR:::::R O:::::O     O:::::O   J:::::::J    E::::::EEEEEEEEEE C:::::C              T:::::T  T:::::T  T:::::T
echo                     P::::P    R:::::::::::::RR  O:::::O     O:::::O   J:::::::J    E:::::::::::::::E C:::::C              T:::::T  T:::::T  T:::::T
echo                     P::::P    R::::RRRRRR:::::R O:::::O     O:::::OJJJ:::::::J     E:::::::::::::::E C:::::C              T:::::T  T:::::T  T:::::T
echo                     P::::P    R::::R     R:::::RO:::::O     O:::::OJ::::::::J      E::::::EEEEEEEEEE C:::::C              T:::::T  T:::::T  T:::::T
echo                     P::::P    R::::R     R:::::RO::::::O   O::::::OJ::::::::J      E:::::E          C:::::C              T:::::T  T:::::T  T:::::T
echo                   PP::::::PP  R::::R     R:::::RO:::::::OOO:::::::OJ::::::::J    EE:::::EEEEEEEEEEEE C:::::C     CCCCCCCT:::::T  T:::::T  T:::::T
echo                   P::::::::P RR:::::R     R:::::ROO:::::::::::::OO JJ:::::::JJ     E::::::::::::::::::::E C:::::CCCCCCCCCTTT::T::TTT::T::T
echo                   P::::::::P RR:::::R     R:::::R OO:::::::::OO    JJJJJJJJJ       E::::::::::::::::::::E  C::::::::::::C  T::T::T  T::T::T
echo                   PPPPPPPPPP RRRRRRR     RRRRRRR   OOOOOOOOO          JJJJJJJ         EEEEEEEEEEEEEEEEEEEEEE   CCCCCCCCCCCCC    TTTTTT   TTTTTT 
echo.

REM Navigate to the project directory
REM This is important because flutter commands need to be run in the project root.
cd "E:\Visionspark\visionspark"
if errorlevel 1 (
    color 0C 
    echo ERROR: Failed to navigate to project directory E:\Visionspark\visionspark
    pause
    exit /b 1
)

REM Run flutter clean
color 0E 
echo ======================================
echo      Running flutter clean...
echo ======================================
echo.
call "C:\Users\dev\flutter\flutter\bin\flutter.bat" clean
if errorlevel 1 (
    color 0C 
    echo ERROR: flutter clean failed.
    pause
    exit /b 1
) else (
    color 0A 
    echo Flutter clean completed successfully.
)
echo.

REM Run flutter pub get
color 0E 
echo ======================================
echo      Running flutter pub get...
echo ======================================
echo.
call "C:\Users\dev\flutter\flutter\bin\flutter.bat" pub get
if errorlevel 1 (
    color 0C 
    echo ERROR: flutter pub get failed.
    pause
    exit /b 1
) else (
    color 0A 
    echo Flutter pub get completed successfully.
)
echo.

color 0F 
echo ======================================
echo      Script finished successfully!    
echo ======================================

REM Pause to see the output before closing
pause 