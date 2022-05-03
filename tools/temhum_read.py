## indoor environment
# temstr = "01100100001010"
# humstr = "01010110100111"
## freezing temperature
# temstr = "00111100011010"
# humstr = "10110111001111"
temstr = input("Enter temperature string: ")
humstr = input("Enter humidity string: ")
temC = (int(temstr, 2)/2**14)*165-40
temF = 9/5*temC+32
humout = (int(humstr, 2)/2**14)*100
print("%.2f celcius degree. %.2f Fahrenheit degree."%(temC, temF))
print("%.2f%% relative humidity."% humout, sep='')
