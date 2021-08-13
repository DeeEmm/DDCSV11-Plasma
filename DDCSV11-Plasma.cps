/******************************************************************************* 
DeeEmm Plasma post processor for DDCSV1/2/3 and Next Wave Automation CNC Shark controllers

12.10.20 - Version 1.0.20101201
    - Corrected millisecond abbreviation

11.10.20 - Version 1.0.20101102
    - Added cut and feed in/out speeds

09.10.20 - Version 1.0.20100901
    - Added scratch start option (added torch type)
    - Added Spot marking operation (using 'drilling' function)
    - Tidied up the code removing unwanted / redundant stuff.
    - Added better comments

06.10.20 - Version 1.0.20100602
    - Removed Z components from moves (relies on last set Z position) 
    - Enabled both M101 (probe down) and M103 (probe up) as both required to generate offset
    - Set G90 before G92 in probe routine
    - Added additional comments to generated code

06.10.20 - Version 1.0.20100601
    - Added manual probe offset 
    - Renamed existing probe offset function to probe distance

05.10.20 - Version 1.0.20100501
    - Tidied comments
    - Removed incorrect M3 (spindle on) commands
    - Removed redundant Z move
    - Changed direction of Z probe action 
    - Modified onPower function for probe operation
    - Tested in Fusion 360 and on DDSCSV 
    
01.10.20 	- Version 1.0.20100101
      - Initial version based on https://www.brainright.com/Projects/CNCController
      - Milling control changed for Plasma control
      - Added pierce delay
      - Added touch off routine
      - Added user selectable cut + pierce height / pierce delay / Z offsets

      

Usage
******************************************************************************** 
NOTE: Set WCS zero as 'stock box top' in setup. (top face of your object)
  This way when z probe measures face and zeros the Z axis, torch offsets will be correct
    
- Copy this file to your Fusion360 'Post' folder on your local machine
- Select DDCSV Post processor in CAM setup within Fusion 360
- Adjust parameters in post processor parameters drop down to suit.

NOTE: If you are using the Spot Marking option you will need to create a separate drilling operation 
for the holes. Choose a generic 3 axis machine for this. The tool is unimportant but it is very important 
to make sure the WCS origin for all operations is set to the same location. Best practice is to use the
'Stock box point' at bottom left / top of stock 

- After drilling operation has been generated change the operation type to 'cutting'
- Make sure that the parent folder ('Settings') is highlighted when you run the post processor to include all tool paths
- You will get a warning about multiple path and the WCS - this is normal (Refer note above)

- More info on the Github page - https://github.com/DeeEmm/DDCSV11-Plasma

  
    
      
Reference
******************************************************************************** 
DDCSV Probe function - http://bbs.ddcnc.com/forum.php?mod=viewthread&tid=150&extra=page%3D1
Autocad post processor reference - https://cam.autodesk.com/posts/reference/classPostProcessor.html
Original file - Copyright 2020 Jay McClellan - http://brainright.com/Projects/CNCController/



License
******************************************************************************** 
This code is provided under the BSD License. A copy of this license is provided below

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 ******************************************************************************/

description = "DDCSV Plasma V1.0.20101201";
vendor = "DeeEmm";
vendorUrl = "https://github.com/DeeEmm/DDCSV11-Plasma";
legal="BSD License";

// TEST: added milling capability to try and 'spot' hole locations using drill function and plasma
capabilities = CAPABILITY_MILLING | CAPABILITY_JET;

certificationLevel = 2;
minimumRevision = 24000;

extension = "tap"; // DDCSV Compatible
setCodePage("ascii");

tolerance = spatial(0.0254, MM);

minimumChordLength = spatial(0.1, MM);
minimumCircularRadius = spatial(0.1, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowSpiralMoves = false;
allowedCircularPlanes = (1 << PLANE_XY); // allow only X-Y circular motion

var gFormat = createFormat({prefix:"G", decimals:1});
var mFormat = createFormat({prefix:"M", decimals:0});
var hFormat = createFormat({prefix:"H", decimals:0});
var dFormat = createFormat({prefix:"D", decimals:0});
var xyzFormat = createFormat({decimals:(3), forceDecimal:true, trim:false});
var feedFormat = createFormat({decimals:(unit == MM ? 0 : 1), forceDecimal:false});
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({prefix:"X", force:true}, xyzFormat);
var yOutput = createVariable({prefix:"Y", force:true}, xyzFormat);
var zOutput = createVariable({prefix:"Z", force:true}, xyzFormat);
var aOutput = createVariable({prefix:"A", force:true}, xyzFormat);

var iOutput = createReferenceVariable({prefix:"I", force:true}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J", force:true}, xyzFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);

var safeRetractZ = 0; // safe Z coordinate for retraction
var showSectionTools = false; // true to show the tool name in each section
var currentCoolantMode = COOLANT_OFF; 
var cutCount = 0;
var operationCount = 0;
var spotMarking = false;


/**********
 * Post processor application dialog parameters 
 * User-defined properties
 *
 *******************/ 
properties = {
  plasmaProbeDistance:20,
  plasmaProbeOffset:-3.101,
  plasmaProbeSpeed:1200,
  plasmaPierceSpeed:200,
  plasmaPierceHeight:4,
  plasmaSpotHeight:1,
  plasmaPierceDelay:1000,
  plasmaSpotMarkDuration:10,
  plasmaCutSpeed:600,
  plasmaPositionSpeed:2000,
  plasmaCutHeight:2.36,
  plasmaPostFlowDelay:5,
  plasmaSafeZ:5,
  plasmaTorchType:"pilotArc"
};


/**********
 *  user-defined property definitions
 *
 *******************/
propertyDefinitions = {
  plasmaTorchType:{
  title:"Plasma Torch Type",
  description:"Select type of torch used. Scratch start will start arc when touching workpiece",
  type: "enum",
   values:[
     {title:"Pilot Arc", id:"pilotArc"},
     {title:"Scratch Start", id:"scratchStart"}
   ]
  },
  plasmaProbeDistance: {title:"Probe Distance", description:"Z axis total travel for probe operation", group:0, type:"spatial"},
  plasmaProbeOffset: {title:"Probe Offset", description:"Floating head activation distance", group:0, type:"spatial"},
  plasmaProbeSpeed: {title:"Probe Speed", description:"Speed of probe operation", group:0, type:"number"},
  plasmaPierceSpeed: {title:"Pierce Speed", description:"Speed of Pierce operation", group:0, type:"number"},
  plasmaPierceHeight: {title:"Pierce Height", description:"Height for pierce operation", group:0, type:"number"},
  plasmaPierceDelay: {title:"Pierce Delay (ms)", description:"Delay in milliseconds after torch on before moving to cut height", group:0, type:"number"},
  plasmaSpotHeight: {title:"Spot Height", description:"Height for spot mark operation", group:0, type:"number"},
  plasmaSpotMarkDuration: {title:"Spot mark duration (ms)", description:"Time in milliseconds torch is on for spot marking", group:0, type:"number"},
  plasmaPostFlowDelay: {title:"Post Flow Delay (ms)", description:"Delay in milliseconds after torch off before moving", group:0, type:"number"},
  plasmaPositionSpeed: {title:"Positioning Speed", description:"Feedrate for intermediate moves", group:0, type:"number"},
  plasmaCutSpeed: {title:"Cut Speed", description:"Feedrate for cut moves", group:0, type:"number"},
  plasmaCutHeight: {title:"Cut Height", description:"Height of torch whilst cutting", group:0, type:"spatial"},
  plasmaSafeZ: {title:"Safe Height", description:"Safe distance of torch above workpiece", group:0, type:"spatial"}
};


/**********
 * writeBlock
 *
 * Writes the specified block.
 *
 *******************/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + (sequenceNumber % 100000), arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}


/**********
 * writeOptionalBlock
 *
 * Writes the specified optional block.
 *
 *******************/
function writeOptionalBlock() {
  if (properties.showSequenceNumbers) {
  var words = formatWords(arguments);
    if (words) {
    writeWords("/", "N" + (sequenceNumber % 10000), words);
    sequenceNumber += properties.sequenceNumberIncrement;
    if (sequenceNumber >= 10000) {
      sequenceNumber = properties.sequenceNumberStart;
    }
    }
  } else {
    writeWords2("/", arguments);
  }
}


/**********
 * formatBoundingBox
 * 
 * Formats a bounding box as a readable string 
 *
 *******************/
function formatBoundingBox(box) {
  return xyzFormat.format(box.lower.x) + " <= X <= " + xyzFormat.format(box.upper.x) + " | " +
  xyzFormat.format(box.lower.y) + " <= Y <= " + xyzFormat.format(box.upper.y) + " | " +
  xyzFormat.format(box.lower.z) + " <= Z <= " + xyzFormat.format(box.upper.z);
}


/**********
 * formatTool
 * 
 * Formats a tool description as a readable string. This is also used to compare tools
 * when warning about multiple tool types, so it will ignore minor tool differences if the
 * main parameters are the same.
 *
 *******************/
function formatTool(tool) {
  var str = "Tool: " + getToolTypeName(tool.type);
  str += ", D=" + xyzFormat.format(tool.diameter) + " " +
  localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
  if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
    str += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
  }
  
  return str;
}


/**********
 * onOpen 
 * Called when post processor is initially run
 * This is where the file header is created
 *
 *******************/
function onOpen() {
  
  writeComment("Created by DeeEmm DDCSV Plasma Post Processor");
  writeComment("https://github.com/DeeEmm/DDCSV11-Plasma");

  if (programName) {
    writeComment("Program: " + programName);
  }
  
  if (programComment) {
    writeComment(programComment);
  }
  
  var globalBounds; // Overall bounding box of tool travel throughout all sections
  var toolsUsed = []; // Tools used (hopefully just one) in the order they are used 
  var toolpathNames = []; // Names of toolpaths, i.e. sections
  
  var numberOfSections = getNumberOfSections(); 
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var boundingBox = section.getGlobalBoundingBox();
    if (globalBounds) {
    globalBounds.expandToBox(boundingBox);
  } else {
    globalBounds = boundingBox;
    toolpathNames.push(section.getParameter("operation-comment"));
  }
  
    if (section.hasParameter('operation:clearanceHeight_value')) {
    safeRetractZ = Math.max(safeRetractZ, section.getParameter('operation:clearanceHeight_value'));
    if (section.getUnit() == MM && unit == IN) {
      safeRetractZ /= 25.4;
    } else if (section.getUnit() == IN && unit == MM) {
      safeRetractZ *= 25.4;
    }       
    }
  }
  
  writeComment("Workpiece:   " + formatBoundingBox(getWorkpiece()));
  writeComment("Tool travel: " + formatBoundingBox(globalBounds));
  writeComment("Safe Z: " + xyzFormat.format(safeRetractZ));

  writeln("G90"); // absolute coordinates
  writeln("M5"); // Make sure spindle is off
  
  
  switch (unit) {
  case IN:
    writeComment("Units: inches");
    writeln("G20"); // inches
    writeln("G64 P0.001"); // precision in inches
    break;
  
  case MM:
    writeComment("Units: millimeters");
    writeln("G21"); // millimeters
    writeln("G64 P0.0254"); // precision in mm
    break;
  }
}


/**********
 * onCommand
 * We're not using this at present bit lets leave it here in case someone wants it to control air etc
 *
 *******************/
function onCommand(command) {
  switch (command) {
    case COMMAND_COOLANT_ON:
      writeln("M08");
    break;
    case COMMAND_COOLANT_OFF:
      writeln("M09");
    break;
  }
}


/**********
 * writeComment
 *
 *******************/
function writeComment(text) {
  text = text.replace(/\(/g," ").replace(/\)/g," ");
  writeln("(--- " + text + " ---)");
}


/**********
 * onComment
 *
 *******************/
function onComment(message) {
  var comments = String(message).split(";");
  for (comment in comments) {
    writeComment(comments[comment]);
  }
}


/**********
 * setCoolant
 *
 *******************/
function setCoolant(coolant) {
  if (coolant != currentCoolantMode) {
   if (coolant == COOLANT_OFF) {
     onCommand(COMMAND_COOLANT_OFF);
   }
   else {
    onCommand(COMMAND_COOLANT_ON);
   }
   currentCoolantMode = coolant;
  }
}


/**********
 * onDwell
 *
 *******************/
function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock(gFormat.format(4), "P" + secFormat.format(seconds));
}


/**********
 * onPower
 *
 * This function is invoked when the power mode changes (used for water jet, laser cutter, and plasma cutter)
 * We are using it for our torch control. The 'power' variable passed to the function controls torch on / off 
 *******************/
function onPower(power) {
  if (power) {
  
  cutCount = cutCount + 1; // Increment the cut count
  writeComment("[START] Probe Z Axis: " + (properties.plasmaProbeDistance) + "mm @ " + (properties.plasmaProbeSpeed) + "mm/s and add " + (properties.plasmaProbeOffset) + "mm floating head offset");
  // probe down until the torch meets the workpiece
  writeBlock(gFormat.format(4), 'P0'); // DND (Do Not Delete)
  writeBlock(mFormat.format(101)); // Enable probe interrupt (skip function)
  writeBlock(gFormat.format(91)); // switch to relative positioning
  writeBlock(gFormat.format(91), 'Z-'+(properties.plasmaProbeDistance), 'F'+(properties.plasmaProbeSpeed)) ; // move downwards until interrupt triggers
  writeBlock(mFormat.format(102));  // disable probe interrupt (skip function) 
  writeBlock(gFormat.format(4), 'P0'); // DND
  
  // probe up until torch clears the workpiece
  writeBlock(mFormat.format(103)); // Enable probe interrupt (skip function)
  writeBlock(gFormat.format(91), 'Z'+(properties.plasmaProbeDistance), 'F'+(properties.plasmaProbeSpeed)) ; // move upwards until interrupt triggers
  writeBlock(mFormat.format(102));  // disable probe interrupt (skip function) 
  writeBlock(gFormat.format(4), 'P0'); // DND 
  
  //set the z location for work surface
  writeBlock(gFormat.format(90)); // switch to absolute positioning
  writeBlock(gFormat.format(4), 'P0'); // DND
  writeBlock(gFormat.format(92), 'Z'+(properties.plasmaProbeOffset)); // set z axis offset 
  writeBlock(gFormat.format(4), 'P0'); // DND
  writeComment("[END] Probe Z");
  
  
  // Let's set up the torch
  
   // If using scratch start torch - turn plasma on when torch is still touching the workpiece
  if (properties.plasmaTorchType == 'scratchStart') { 
    writeComment("[SCRATCH START]");
    writeBlock(gFormat.format(0), 'Z-1'); // move towards workpiece (this is just an arbitrary distance as torch moves away during probe routine and may not be touching the workpiece)
    writeln("S500 M3"); // This is the correct DDCSV Format for spindle (torch) control. We need the speed declaration if parameter #220 is set to 'Gcode' (which is advisable else torch turns on as soon as job starts)
    writeBlock(gFormat.format(4), 'P0'); // DND       
  }
  
  // Are we cutting through or just spot marking?
  if (spotMarking == true) {
    // We're spotMarking - Lets do a Spot mark!!
    writeComment("[START] Spot Mark - Operation #" + cutCount + " @ " + (properties.plasmaSpotHeight) + "mm Spot Height with " + (properties.plasmaSpotMarkDuration) + "ms Spot Mark Duration");      
    // turn on the torch (if its not already on)
    writeln("S500 M3"); // correct DDCSV Format for spindle control.
    writeBlock(gFormat.format(0), 'Z',(properties.plasmaCutHeight), 'F'+(properties.plasmaPierceSpeed)); // move up to cut height
    writeBlock(gFormat.format(4), 'P'+(properties.plasmaSpotMarkDuration)); // wait for spot duration
    writeBlock(mFormat.format(5)); // lets turn the torch off. just in case someone programmed some moves afterwards
      
  } else {      

    // We're cutting through - Lets start a cut!!
    writeComment("[START] Cut Path - Operation #" + cutCount + " @ " + (properties.plasmaPierceHeight) + "mm Pierce Height & " + (properties.plasmaCutHeight) + "mm Cut Height with " + (properties.plasmaPierceDelay) + "ms Pierce Delay");
    writeBlock(gFormat.format(0), 'Z'+(properties.plasmaPierceHeight), 'F'+(properties.plasmaPositionSpeed)); // move to pierce height
    // turn on the torch (if its not already on)
    writeln("S500 M3"); // correct DDCSV Format for spindle control.
    writeBlock(gFormat.format(4), 'P'+(properties.plasmaPierceDelay)); // wait for plasma delay
    writeBlock(gFormat.format(0), 'Z',(properties.plasmaCutHeight), 'F'+(properties.plasmaPierceSpeed)); // move down to cut height
    writeln('F'+(properties.plasmaCutSpeed)); // Set the cut feed rate
    // We're now cutting!! WOOT!!
    // the rest of the moves on the path are processed by the 'onLinear' and 'OnCircular' functions
    
    
  }
  
  } else { //no power so do torch off and lift head clear of workpiece

  if (spotMarking == true) {
    writeComment("[END] Spot Mark - Operation #" + cutCount);        
  } else {
    writeComment("[END] Cut Path - Operation #" + cutCount);        
  }
    
  spotMarking = false;

  writeln('F'+(properties.plasmaPositionSpeed)); // Set the positioning feed rate
  writeBlock(mFormat.format(5)), writeBlock(gFormat.format(0), 'Z',(properties.plasmaSafeZ));
  writeBlock(gFormat.format(4), 'P',(properties.plasmaPostFlowDelay)); // wait for post flow delay   
  }
}


/**********
 * onCyclePoint
 * This is called for each drilling operation it includes the hole location
 * We've hacked it to move to our spot mark locations and call the torch control function (onPower) instead.
 * It's a complete bastardisation of its intended use. But it works.
 *
 *******************/
function onCyclePoint(x, y, z, r) {

  // If we're in this function we are 'drilling' (spot marking) so let's set a var we can use later on.
  spotMarking = true;
  
  writeComment("Operation #" + ( cutCount + 1) + " Move to Spot Mark Location"); // tell the world
  writeBlock(gFormat.format(0), 'X'+ x, 'Y'+ y); // move above the hole
  
  onPower(1); // lets cheat and call the plasma function
  onPower(0); // lets call the plasma function again with the 'power' set to '0'

 }


/**********
 * onRapid
 *
 *******************/
function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
  writeln("G00 " + x + " " + y); // we control Z height via the plasma torch control routine (onPower)
  }
}


/**********
 * onLinear
 *
 *******************/
function onLinear(_x, _y, _z, feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);

  if (x || y || z) {
  writeln("G01 " + x + " " + y + f); // we control Z height via the plasma torch control routine (onPower)
  }
}


/**********
 * onCircular
 *
 *******************/
function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  var start = getCurrentPosition();  
  var f = feedOutput.format(feed);
  
  if (f) {
    writeln(f);
  }
  
  writeln((clockwise ? "G02 " : "G03 ") + 
  xOutput.format(x) + " " +
  yOutput.format(y) + " " +
  iOutput.format(cx - start.x, 0) + " " +
  jOutput.format(cy - start.y, 0)); // we control Z height via the plasma torch control routine (onPower)
  
  
 }


/**********
 * onClose
 *
 *******************/
function onClose() {
  writeComment("JOB FINISH");

  writeln("G00 " + zOutput.format(safeRetractZ)); // retract to safe Z

  setCoolant(COOLANT_OFF); // turn air off?

  onImpliedCommand(COMMAND_STOP_SPINDLE); 
  writeln("M5"); // turn plasma off
  onImpliedCommand(COMMAND_END);
  writeln("M2");
}


/**********
 * onCycle
 *
 *******************/
function onSection() {
  operationCount = operationCount + 1;
  writeComment("Setup #" + operationCount);
}