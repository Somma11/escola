from art import *
import os

if(os.name == nt):
    os.system('cls')

else:
    os.system('clear')

text = text2art('Hello World!!', '4max')

deco = lprint(length=14, char="-+=")

print('\033[0;36m' + '\033[1m' + deco + text + deco + '\033[0m' + '\033[1m')
