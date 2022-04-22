print("Character array generator program running.")
obj = input()
objlen = len(obj)
idx = 1
# print out the ASCII codes refer to characters in this string
print('(x"0d", x"0a", ', end='')
for charr in obj:
    if(idx < objlen):
        # print("x\"%d\", "%(hex(ord(charr))), sep='', end='')
        print("x\"%x\", "%(ord(charr)), sep='', end='')
    else:
        print("x\"%x\", x\"0a\", x\"0d\");"%(ord(charr)), sep='', end='\n')
    idx += 1
# print out the string in VHDL comment
# and length of string including CRLF
print("--", obj)
print("-- string length containing CRLF on head and tail:", objlen+4)