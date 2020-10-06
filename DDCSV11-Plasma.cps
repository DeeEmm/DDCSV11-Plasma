/******************************************************************************* 
DeeEmm Plasma post processor for DDCSV1.1 and Next Wave Automation CNC Shark controllers

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
NOTE: Set WCS zero as stock box top in setup. (top face of your object)
    This way when z probe measures face and zeros the Z axis, torch offsets will be correct
    
- Copy this file to your Fusion360 'Post' folder on your local machine
- Select DDCSV Post processor in CAM setup within Fusion 360
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

description = "DDCSV1.1 Plasma V1";
vendor = "DeeEmm";
vendorUrl = "https://github.com/DeeEmm/DDCSV11-Plasma";
legal="BSD License";

capabilities = CAPABILITY_JET;

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


/**********
 * user-defined properties
 *
 *******************/ 
properties = {
  dwellInSeconds: true, 
  G31_PROBE_DISTANCE:-50,
  G31_PROBE_OFFSET:0,
  G31_PROBE_SPEED:200,
  G31_PIERCE_HEIGHT:4,
  G31_PIERCE_DELAY:5,
  G31_CUT_HEIGHT:1.5,
  G31_SAFE_Z:16
};


/**********
 *  user-defined property definitions
 *
 *******************/
propertyDefinitions = {
	dwellInSeconds: {title:"Dwell in seconds / milliseconds", description:"True = Seconds / False = Milliseconds", group:0, type:"number"},
  G31_PROBE_DISTANCE: {title:"Probe Distance", description:"Distance of probe operation", group:0, type:"number"},
  G31_PROBE_OFFSET: {title:"Probe Offset", description:"Torch offset adjustment", group:0, type:"number"},
  G31_PROBE_SPEED: {title:"Probe Speed", description:"Speed of probe operation", group:0, type:"number"},
	G31_PIERCE_HEIGHT: {title:"Pierce Height", description:"Height for pierce operation", group:0, type:"number"},
	G31_PIERCE_DELAY: {title:"Pierce Delay", description:"Time torch is held after pierce move", group:0, type:"number"},
	G31_CUT_HEIGHT: {title:"Cut Height", description:"Height of torch whilst cutting", group:0, type:"number"},
	G31_SAFE_Z: {title:"Safe Height", description:"Safe distance of torch above workpiece", group:0, type:"number"},
};


/**********
 *  writeBlock
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
 *
 * Lets' create the file header
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
   
	// This builds up the list of tools used in the order they are encountered, whereas getToolTable() returns an unordered list
	var tool = section.getTool();
	var desc = formatTool(tool);
	if (toolsUsed.indexOf(desc) == -1)
	  toolsUsed.push(desc);
  }

  // Normal practice is to run one post with all paths having exactly the same tool, but in some cases differently-defined tools
  // may actually be the same physical tool but with different nominal feeds etc. This warning is only shown when the formatted tool
  // descriptions differ.
  if (toolsUsed.length > 1) {
	  var answer = promptKey2("WARNING: Multiple tools are used, but tool changes are not supported.", toolsUsed.join("\r\n") + "\r\n\r\nContinue anyway?", "YN");
	
    if (answer != "Y") error("Tool changes are not supported");
	  showSectionTools = true; // show the tool type used in each section.
  }

  writeComment((numberOfSections > 1 ? "Toolpaths: " : "Toolpath: ") + toolpathNames.join(", "));
  
  for (var i=0; i<toolsUsed.length; ++i) {
	  writeComment(toolsUsed[i]);
  }
  
  writeComment("Workpiece:   " + formatBoundingBox(getWorkpiece()));
  writeComment("Tool travel: " + formatBoundingBox(globalBounds));
  writeComment("Safe Z: " + xyzFormat.format(safeRetractZ));

  writeln("G90"); // absolute coordinates
  
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
  writeln("(" + text + ")");
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
 * invoked when the power mode changes (used for water jet, laser cutter, and plasma cutter)
 * NOTE: onPower looks to be invoked by solo Z axis movement
 * 'power' variable effectively controls torch operation
 *******************/
function onPower(power) {
  if (power) {
    writeComment("--- Touch Off ---");
    writeBlock(mFormat.format(101)); // Enable probe interrupt (skip function)
    writeBlock(gFormat.format(91)); // switch to relative positioning
    writeBlock(gFormat.format(91), 'Z'+(properties.G31_PROBE_DISTANCE), 'F'+(properties.G31_PROBE_SPEED)) ; // move downwards until interrupt triggers
    writeBlock(gFormat.format(92), 'Z'+(properties.G31_PROBE_OFFSET)); // set z axis to zero 
    writeBlock(gFormat.format(90)); // switch back to absolute positioning
    writeBlock(mFormat.format(102));  // disable probe interrupt (skip function) 
    writeBlock(gFormat.format(0), 'Z',(properties.G31_PIERCE_HEIGHT)); // move to pierce height
    writeComment("--- Torch On ---");
    writeBlock(mFormat.format(3)); // plasma on
    writeBlock(gFormat.format(4), 'P',(properties.G31_PIERCE_DELAY)); // wait for plasma delay
    writeBlock(gFormat.format(0), 'Z',(properties.G31_CUT_HEIGHT)); // move down to cut height
  } else {
    writeComment("--- Torch off ---");
    writeBlock(mFormat.format(5)),
    writeBlock(gFormat.format(0), 'Z',(properties.G31_SAFE_Z));
  }
}

/**********
 * onSection
 *
 *******************/
function onSection() {
  if (hasParameter("operation-comment")) {
  	var comment = getParameter("operation-comment");
  	if (comment) {
  	  writeComment("--- " + comment + " ---");
  	}
  }
  
  // TODO - expand tool selection to include water jet + laser
  // Checkout GRBL PP for additional clauses
  
  // We only show the tool in each section if there are multiple tools
  if (showSectionTools) {
	  writeComment(formatTool(currentSection.getTool()));
  }
  
  setCoolant(tool.coolant);

//  writeln("S " + currentSection.getTool().spindleRPM); // spindle speed
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
	  writeln("G00 " + x + " " + y + " " + z);
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
	  writeln("G01 " + x + " " + y + " " + z + " " + f);
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
	zOutput.format(z) + " " +
	iOutput.format(cx - start.x, 0) + " " +
	jOutput.format(cy - start.y, 0));
}

/**********
 * onOrientateSpindle
 *
 *******************/
function onOrientateSpindle(_a) {
  var a = xOutput.format(_a);
  if (a) {
	  writeln("G01 " + a);
  }
}

/**********
 * onClose
 *
 *******************/
function onClose() {
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
function onCycle() {
	
}