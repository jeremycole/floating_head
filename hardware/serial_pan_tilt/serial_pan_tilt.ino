#include <Servo.h> 
 
Servo pan, tilt;

String inputString = "";         // a string to hold incoming data
boolean stringComplete = false;  // whether the string is complete

void setup() 
{
  Serial.begin(9600);
  inputString.reserve(200);
  pan.attach(9);
  pan.write(90);
  tilt.attach(10);
  tilt.write(90);
} 
 
void loop() 
{
  if(stringComplete)
  {
    if(inputString.substring(0,1) == "H")
    {
      pan.write(90);
      tilt.write(90);
      Serial.println("Going home");
    }
    if(inputString.substring(0,1) == "P")
    {
      char pan_value = inputString.substring(1).toInt();
      pan.write(pan_value);
      Serial.println("Moving pan");
    }
    if(inputString.substring(0,1) == "T")
    {
      char tilt_value = inputString.substring(1).toInt();
      tilt.write(tilt_value);
      Serial.println("Moving tilt");
    }

    inputString = "";
    stringComplete = false;
  }
}

void serialEvent() {
  while (Serial.available()) {
    // get the new byte:
    char inChar = (char)Serial.read(); 
    // add it to the inputString:
    inputString += inChar;
    // if the incoming character is a newline, set a flag
    // so the main loop can do something about it:
    if (inChar == '\n') {
      stringComplete = true;
    } 
  }
}
