# temstr = "01100100001010"
# humstr = "01010110100111"
temstr = "00111100011010"
humstr = "10110111001111"
temout = (int(temstr, 2)/2**14)*165-40
humout = (int(humstr, 2)/2**14)*100
print(temout, "celcius degree.")
print(humout, "% relative humidity.", sep='')