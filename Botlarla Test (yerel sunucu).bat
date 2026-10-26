@echo off
rem Botlarla test: bilgisayardaki yerel sunucuya baglanir. Kara Tahta atlanir (diger 6 oyun oynanir).
start "" "D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\HatDustu" -- server=ws://127.0.0.1:8794 oyunlar=devre,kimkim,yalanci,rulet,c4,ortalama
