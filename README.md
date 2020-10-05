# DDCSV11-Plasma

DDCSV11 Plasma post processor for fusion 360  
Includes touch off / pierce routines

This post processor uses a floating head with manual touch-off 'probe' function to detect the workpiece Z height each time the torch is turned on. The code uses the 'onPower' function, a system function that is called by Fusion360 when it detects a change in Z location. This can then be used for torch on and torch off routines including probing and touch off.

The 'Probe Offseet' value sets the distance that the probing operation will travel. If your probe function moves in the incorrect direction, simply change the sign of the value.

The onPower function is only available in jet cutting mode


## Configuration

To add the post processor to your machine you will need to copy the file to Fusion360s ‘post’ folder.

On a mac this resides in

Users>MAC USERNAME>Library>Containers>com.autodesk.mas.fusion360>Data>Autodesk>Fusion 360 CAM>Posts

You will need to make hidden files visible to be able to see the Library folder. You can either do this by pressing the OPTION key whilst viewing the ‘Go’ menu in Finder, or you can toggle the visibility of all hidden files by pressing ‘CMD + SHIFT + .’ whist in Finder.

On a windows machine the path is different (sorry cannot help you there)


## Usage

- Make your 2D part in fusion 360
- Go to the manufacture page
- Create a setup using a plasma tool
- Select the paths you want to cut by clicking on the paths 
- Make sure that the cut direction arrows are on the outside of the workpiece
- Go to the Additive menu and select post process
- Select personal posts from the source dialog
- Here you should see the post processor file you added above - DDCSV11-Plasma
- Change the settings for pierce height / pierce delay etc to suit your workpiece.
- Hit the OK button to create your Gcode.  

---

If you find this file of use, please pay it forwards with a random act of kindness.
