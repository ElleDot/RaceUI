import org.gamecontrolplus.gui.*;
import org.gamecontrolplus.*;
import net.java.games.input.*;

import sprites.utils.*;
import sprites.maths.*;
import sprites.*;

ControlIO control;
ControlDevice stick;

Sprite playerSprite, needleSprite;
StopWatch timer;
int alphaVal = 255;
int lightCounter = 0;
int menuCooldown = 60;

// This will change depending on the course selected;
// In degrees, 0 = East, 90 = South, 180 = West, 270 = North
float[] startingDirection = {0, 180, 180, 0, 160};
int playerStartX, playerStartY;
float playerDirection = 0, currentAcceleration = 0, playerSpeed = 0, targetSpeed = 0, cachedSpeed = 0, accelInput = 0, brakeInput = 0;
float playerMaxReverseSpeed = -51;
float dialScale = (PI*1.5);

// 1 - Deux Cent Cinq (Peugeot 205)
// 2 - Eight6         (Toyota Trueno AE86)
// 3 - Das Auto       (M-B W154)
// 4 - TG-40          (Ford GT40)
// 5 - Volta Mk. 3    (Tesla Model 3)
int carSelected = 1;

// 1 - Brands Hatch Indy
// 2 - Donington
// 3 - Silverstone National
// 4 - Snetterton
int trackSelected = 1;
String carName, trackName;
FloatList lapRecords;
String[] lines;

// Actual car top speeds in kmh^-1!!
float[] playerMaxSpeed = { 0, 210, 201, 328, 263, 225 };
float[] playerAccelRate = { 0, 0.02, 0.02, 0.01, 0.015, 0.04 };
float[] playerTurnRate = { 0, 0.1, 0.12, 0.09, 0.09, 0.08 };
float[] playerDecelRate = { 0, 0.01, 0.005, 0.02, 0.015, 0.005 };

// The size of the asphalt and grass textures, by width and height
int textureSize = 20;
Sprite[] concrete, asphalt, finishLine, tyreWalls, checkPoints;
PImage menuImage, acceleratorImage, brakeImage, speedoImage, carPreviewImage, trackPreviewImage, backImage, lightImage, scoresImage;
PGraphics lightLayer;

// 0 - Main Menu
// 1 - Loading in/countdown
// 2 - In Game
int gameState = 0;
boolean checkpointHit = false, scoresShown = false;
float playTime = 0, lastLapTime = 0, bestLapTime = 0;

public void setup() {
  
  size(1280, 720);
  lightLayer = createGraphics(width,height);
  
  // Initialise the ControlIO then the controller
  control = ControlIO.getInstance(this);
  stick = control.filter(GCP.STICK).getMatchedDevice("controlMethodA");
  
  // null check to see if a correct controller was supplied
  if (stick == null) {
    // Bad state, kill the program
    println("No suitable device configured");
    System.exit(-1); 
  }

  // Load images used for various UI pieces
  menuImage = loadImage("UI/instructions.png");
  speedoImage = loadImage("UI/SpeedDial.png");
  acceleratorImage = loadImage("UI/accelerator.png");
  brakeImage = loadImage("UI/brake.png");
  carPreviewImage = loadImage("UI/car"+carSelected+".png");
  trackPreviewImage = loadImage("UI/track"+trackSelected+".png");
  backImage = loadImage("UI/startSelect.png");
  scoresImage = loadImage("UI/scoreBackground.png");
  
}

public void loadMap() {
  
  // Load map times here
  lines = loadStrings("data/times.txt");
  lapRecords = new FloatList();
  for (int i = 0; i < lines.length; i++) {
    lapRecords.append(float(lines[i]));
  }

  bestLapTime = float(lines[((trackSelected-1)*5) + carSelected - 1]);
  lastLapTime = 0;
  playTime = 0;
  gameState = 1;
  
  println("Best time on " + getTrackName(trackSelected) + " in the " + getCarName(carSelected)+ " (" + trackSelected + 
    "-" + carSelected + ") is " + bestLapTime);
  
  // Create the lap timer if one doesn't exist
  // The old one is re-used if one is already present!
  if (timer == null) { timer = new StopWatch(); } else { timer.reset(); }
  
  // Uses a base 'trackX.png' image to generate a playable map
  PImage map = loadImage("Tracks/" + trackSelected + ".png");
  
  // Initialise ArrayLists to make handling the collections easier
  ArrayList<Sprite> walls = new ArrayList<Sprite>();
  ArrayList<Sprite> roads = new ArrayList<Sprite>();
  ArrayList<Sprite> checkpoints = new ArrayList<Sprite>();
  ArrayList<Sprite> chequered = new ArrayList<Sprite>();
  ArrayList<Sprite> tyres = new ArrayList<Sprite>(); 
  Sprite s;
  
  // generate playable map from the base track image
  for (int y = 10; y < width; y += textureSize) {
    for (int x = 10; x < width; x += textureSize) {
      int c = map.get(x, y) & 0x00ffffff;
      int r = (c >> 16) & 0xff;
      int g = (c >> 8) & 0xff;
      int b = c & 0xff;
      
      if (r == 255 && g == 0 && b == 0) { // Asphalt, no collision
        s = new Sprite(this, "Textures/asphalt.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 0 && g == 255 && b == 0) { // Finish line AND start point
        s = new Sprite(this, "Textures/chequered.png", 50);
        s.setXY(x, y);
        chequered.add(s);
        playerStartX = x;
        playerStartY = y;
      } else if (r == 255 && g == 255 && b == 0) { // Finish line, no collision
        s = new Sprite(this, "Textures/chequered.png", 50);
        s.setXY(x, y);
        chequered.add(s);
      } else if (r == 255 && g == 0 && b == 255) { // Edge of road, normal
        s = new Sprite(this, "Textures/lightAsphalt.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 0 && g == 192 && b == 0) { // CHECKPOINT - ROAD TEXTURE
        s = new Sprite(this, "Textures/asphalt.png", 50);
        s.setXY(x, y);
        checkpoints.add(s);
      } else if (r == 0 && g == 128 && b == 0) { // CHECKPOINT - ROAD EDGE
        s = new Sprite(this, "Textures/lightAsphalt.png", 50);
        s.setXY(x, y);
        checkpoints.add(s);
      } else if (r == 192 && g == 0 && b == 192) { // Kerb NS
        s = new Sprite(this, "Textures/kerbNS.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 128 && g == 0 && b == 128) { // Kerb EW
        s = new Sprite(this, "Textures/kerbEW.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 0 && g == 0 && b == 255) { // walls with stopping collision
        s = new Sprite(this, "Textures/concrete.png", 50);
        s.setXY(x, y);
        walls.add(s);
      } else if (r == 0 && g == 255 && b == 255) { // Tyre walls NS, bouncy collision 
        s = new Sprite(this, "Textures/tyreWallNS.png", 50);
        s.setXY(x, y);
        tyres.add(s);
      } else if (r == 0 && g == 128 && b == 128) { // Tyre walls EW, bouncy collision 
        s = new Sprite(this, "Textures/tyreWallEW.png", 50);
        s.setXY(x, y);
        tyres.add(s);
      } else if (r == 64 && g == 64 && b == 64) { // East-facing start grid
        s = new Sprite(this, "Textures/gridE.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 96 && g == 96 && b == 96) { // South-facing start grid
        s = new Sprite(this, "Textures/gridSW.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 128 && g == 128 && b == 128) { // West-facing start grid
        s = new Sprite(this, "Textures/gridW.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 255 && g == 128 && b == 0) { // Crowd Stand
        s = new Sprite(this, "Textures/standNM.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 255 && g == 64 && b == 0) { // Front Crowd Stand
        s = new Sprite(this, "Textures/standFM.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 255 && g == 96 && b == 0) { // Crowd Stand L
        s = new Sprite(this, "Textures/standNL.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 255 && g == 32 && b == 0) { // Crowd Stand R
        s = new Sprite(this, "Textures/standNR.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 0 && g == 64 && b == 0) { // tree Texture
        s = new Sprite(this, "Textures/tree.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else if (r == 0 && g == 32 && b == 0) { // grass alt texture
        s = new Sprite(this, "Textures/grass2.png", 50);
        s.setXY(x, y);
        roads.add(s);
      } else { // grass tile texture, in case map colour is not recognised or is left blank
        s = new Sprite(this, "Textures/grass.png", 50);
        s.setXY(x, y);
        roads.add(s);
      }
    }
  }
  
  // Convert arraylists to arrays for SPEEDY processing
  concrete = walls.toArray(new Sprite[walls.size()]);
  asphalt = roads.toArray(new Sprite[roads.size()]);
  finishLine = chequered.toArray(new Sprite[chequered.size()]);
  tyreWalls = tyres.toArray(new Sprite[tyres.size()]);
  checkPoints = checkpoints.toArray(new Sprite[checkpoints.size()]);
  
  // Set the car sprite up
  String carFilePath = "Cars/" + carSelected + ".png";
  playerSprite = new Sprite(this, carFilePath, 100);
  // Set the dial needle sprite up 
  String needlePath = "UI/dialNeedle.png";
  needleSprite = new Sprite(this, needlePath, 100);
  needleSprite.setXY(width-64, 64);
  
  // Initialise the game start position
  initGameStart();
  
}

void drawLights(int lightCounter) {
  lightImage = loadImage("UI/lights"+lightCounter+".png");
  lightLayer.beginDraw();
  lightLayer.imageMode(CENTER);
  lightLayer.tint(255,255-(lightCounter-240));
  lightLayer.image(lightImage,width/2,height/2);
  lightLayer.endDraw();
  image(lightLayer,0,0);
}

public void initGameStart() {
  
  // Set position of car, speed of car, rotation, game state, etc.
  playTime = 0;
  lightCounter = 0;
  playerSpeed = 0;
  playerDirection = radians(startingDirection[trackSelected]);
  playerSprite.setXY(playerStartX, playerStartY);
  playerSprite.setRot(playerDirection);
  playerSprite.setSpeed(playerSpeed, playerDirection);
  checkpointHit = false;
}

void drawMenu() {
  
  if (scoresShown) {
    surface.setTitle("RaceUI - Lap Records for " + getTrackName(trackSelected) + " - " + int(frameRate));
  } else {
    surface.setTitle("RaceUI - Car and Course Select - " + int(frameRate)); 
  }
  processUserMenuInput();
  
  imageMode(CORNER);
  image(menuImage, 0, 0);
  textAlign(LEFT,CENTER);
  fill(255);
  text("RaceUI v1.1.1 - 14/11/20",10,10);
  text("ElleDot 2020",10,30);
  image(carPreviewImage,width*0.03,height*0.5);
  image(trackPreviewImage,width*0.03,height*0.7);
  
  if (alphaVal > 0) {
    fill(0,alphaVal);
    rect(0,0,width,height); 
    alphaVal = (int)lerp(alphaVal, 0, 0.05);
  }
  
  if (scoresShown) {
    
    lines = loadStrings("times.txt");
    
    image(scoresImage,0,0,width,height);
    textAlign(CENTER,CENTER);
    fill(#3c3c3c);
    textSize(20);
    text("For " + getTrackName(trackSelected), width/2, height*0.33);
    
    textAlign(LEFT,CENTER);
    for (int i = 0; i < 5; i++) {
      text(getCarName(i+1) + ":",width*0.35,height*0.5 + (i*(0.04*height)));
    }
    
    textAlign(RIGHT,CENTER);
    for (int i = 0; i < 5; i++) {
      float rawTime = float(lines[i + (trackSelected-1)*5]);
      int mins = (int) rawTime / 60;
      text(mins + ":" +  nf(rawTime-(mins*60), 2, 3),width*0.65,height*0.5 + (i*(0.04*height)));
    }
    textSize(12); // Return it to normal once more
  }
  
}

String getTrackName(int trackNumber) {
  switch (trackNumber) {
    case 1:
      trackName = "Brands Hatch Indy Circuit";
      break;
    case 2:
      trackName = "Donington Park";
      break;
    case 3:
      trackName = "Silverstone National Circuit";
      break;
    case 4:
      trackName = "Snetterton";
      break;
  }
  return trackName;
}

String getCarName(int carNumber) {
  switch (carNumber) {
    case 1:
      carName = "le Deux Cent Cinq";
      break;
    case 2:
      if (scoresShown) {
        carName = "Retro Eight-6";
      } else {
        carName = "the Retro Eight-6";
      }
      break;
    case 3:
      carName = "Das Auto";
      break;
    case 4:
      if (scoresShown) {
        carName = "TG-40";
      } else {
        carName = "the TG-40";
      }
      break;
    case 5:
      if (scoresShown) {
        carName = "Volta Mk.3";
      } else {
        carName = "the Volta Mk.3";
      }
      break;
  }
  return carName;
}

void drawRace() {
  
  surface.setTitle("RaceUI - Racing at " + getTrackName(trackSelected) + " in " + getCarName(carSelected) + " - " + int(frameRate));
  
  //Draw textures here
  for (Sprite s : concrete)
    s.draw();
  for (Sprite s : asphalt)
    s.draw();
  for (Sprite s : finishLine)
    s.draw();
  for (Sprite s : tyreWalls)
    s.draw();
  for (Sprite s : checkPoints)
    s.draw();
    
  playerSprite.draw();
  
  if (gameState != 1) {
    processUserGameInput();
    playTime = (float) timer.getRunTime();
    float deltaTime = (float) timer.getElapsedTime();
    updateAllSprites(deltaTime);
    processCollisions(deltaTime);
  } else {
    fill(0,128);
    rect(0,0,width,height);
  }
    
  
  showStatus((float) playTime, accelInput, brakeInput);
  
  if (lightCounter < 360) {
    
    lightCounter++;
    int lightImageCounter = (lightCounter/60)+1;
    if (lightImageCounter > 5) lightImageCounter = 5;
    
    if (lightCounter == 240) {
      //Countdown ended, lap time live, controls active
      timer.reset();
      gameState = 2;
    }
    drawLights(lightImageCounter);
  }    
}

public void draw() {
  if (menuCooldown > 0) menuCooldown--;
  if (gameState == 0) { drawMenu(); } else { drawRace(); }
}

void showStatus(float lapTime, float accelInput, float brakeInput) {
  
  fill(255);
  noStroke();
  textAlign(RIGHT,CENTER);
  if (playerSpeed>350) playerSpeed = 350;
  if (playerSpeed<-50) playerSpeed = -50;
  currentAcceleration = (playerSpeed - cachedSpeed) * 10;
  if (currentAcceleration > 50) currentAcceleration = 50;
  if (currentAcceleration < -25) currentAcceleration = -25;
  cachedSpeed = playerSpeed;
  
  // Player Speed
  imageMode(CENTER);
  image(speedoImage, width-speedoImage.width*0.5, speedoImage.height/2);
  
  // Handle needle rotation
  float speedPercent = abs(playerSpeed) / 328;
  needleSprite.setRot(radians(-135 + (speedPercent*270)));
  needleSprite.draw();
  
  imageMode(CORNERS);
  image(backImage, height*0.01, height*0.01);
  textAlign(LEFT,CENTER);
  text("Return to menu", width*0.035,height*0.03);
  text("Reset car & timer", width*0.035,height*0.085);
  
  //// Accelerator/Brake Pedal representation of the triggers
  imageMode(CORNER);
  image(acceleratorImage, width-acceleratorImage.width-speedoImage.width, 0, acceleratorImage.width, acceleratorImage.height-(acceleratorImage.height*(accelInput+1)*0.25));
  image(brakeImage, width-brakeImage.width-acceleratorImage.width-speedoImage.width, 0, brakeImage.width, brakeImage.height-(brakeImage.height*(brakeInput+1)*0.25));
  textAlign(CENTER, TOP);
  text(int(playerSpeed) + " km/h", width-(speedoImage.width*0.5),speedoImage.height);
  
  int mins = ((int)lapTime/60);
  int lastMins = ((int)lastLapTime/60);
  int bestMins = ((int)bestLapTime/60);
  
  // The text for the lap timers
  textAlign(RIGHT,CENTER);
  text("Lap timer", width-(speedoImage.width)-(brakeImage.width*2)-70,16);
  text("Last lap",width-(speedoImage.width)-(brakeImage.width*2)-70,32);
  text("Lap Record",width-(speedoImage.width)-(brakeImage.width*2)-70,48);
  text(mins + ":" + nf(lapTime-(mins*60), 2, 3),width-(speedoImage.width)-(brakeImage.width*2)-8,16);
  if (lastLapTime == bestLapTime && bestLapTime != 0) { fill(255,128,255); } else { fill(255); }
  text(lastMins + ":" + nf(lastLapTime-(lastMins*60), 2, 3),width-(speedoImage.width)-(brakeImage.width*2)-8,32);
  if (bestLapTime > 0) { fill(255,128,255); } else { fill(255); }
  text(bestMins + ":" + nf(bestLapTime-(bestMins*60), 2, 3),width-(speedoImage.width)-(brakeImage.width*2)-8,48);
  
}

// Handles collisions between the car and walls, checkpoints, etc.
public void processCollisions(float deltaTime) {
  
  // Car hits a wall, stops dead
  for (int i = 0; i < concrete.length; i++) {
    if (playerSprite.bb_collision(concrete[i])) {
      float xPos = (float) playerSprite.getX();
      float yPos = (float) playerSprite.getY();
      float xVel = (float) playerSprite.getVelX();
      float yVel = (float) playerSprite.getVelY();
      xPos -= 3 * xVel * deltaTime;
      yPos -= 3 * yVel * deltaTime;
      playerSprite.setXY(xPos, yPos);
      playerSprite.setVelXY(0, 0);
      playerSpeed = 0;
      playerSprite.stopImageAnim();        
      break;
    }
  }
  
  // Car collides with tyre wall, bounces off
  for (int i = 0; i < tyreWalls.length; i++) {
    if (playerSprite.bb_collision(tyreWalls[i])) {
      float xPos = (float) playerSprite.getX();
      float yPos = (float) playerSprite.getY();
      float xVel = (float) playerSprite.getVelX();
      float yVel = (float) playerSprite.getVelY();
      xPos -= 3 * xVel * deltaTime;
      yPos -= 3 * yVel * deltaTime;
      playerSprite.setXY(xPos, yPos);
      playerSprite.setVelXY(0, 0);
      playerSpeed = -playerSpeed;
      playerSprite.stopImageAnim();        
      break;
    }
  }
  
  // Car crosses checkpoint
  for (int i = 0; i < checkPoints.length; i++) {
    if (playerSprite.bb_collision(checkPoints[i])) {
      if (!checkpointHit) {
        checkpointHit = true;
        println("car crossed checkpoint!");
        break;
      }
    }
  }
  
  // Car crosses finish line, check for lap completion
  for (int i = 0; i < finishLine.length; i++) {
    if (playerSprite.bb_collision(finishLine[i])) {
      lapCompleteCheck();
      break;
    }
  }
}

void lapCompleteCheck() {
 
  if (checkpointHit) {
    println("Lap complete - " + playTime + " seconds.");
    checkpointHit = false;
    lastLapTime = playTime;
    if (lastLapTime < bestLapTime || bestLapTime == 0) { 
      
      // Player just drove a best lap!
      bestLapTime = playTime;
      String[] timesToWrite = new String[lines.length];
      
      for (int i = 0; i < lapRecords.size(); i++) {
        if (i != ((trackSelected-1)*5) + carSelected - 1) {
          timesToWrite[i] = str(lapRecords.get(i));
        } else {
          timesToWrite[i] = str(bestLapTime);
        }
      }
      
      // Writes the new best time to the save file
      saveStrings("data/times.txt", timesToWrite);
      
    }
    // Flash white for a frame, showing lap completion.
    background(255);
    timer.reset();
  }
}

// Forced sprite update
public void updateAllSprites(float deltaTime) {
  playerSprite.update(deltaTime);
}

// Handles Controller input while on the menu
public void processUserMenuInput() {
  
  if (menuCooldown == 0) {
    
    if (stick.getButton("dUp").pressed() && !scoresShown) {
      carSelected++;
      if (carSelected > 5) carSelected = 1;
      carPreviewImage = loadImage("UI/car"+carSelected+".png");
      menuCooldown = int(frameRate * 0.333);
    } else if (stick.getButton("dDown").pressed() && !scoresShown) {
      carSelected--;
      if (carSelected < 1) carSelected = 5;
      carPreviewImage = loadImage("UI/car"+carSelected+".png");
      menuCooldown = int(frameRate * 0.333);
    } else if (stick.getButton("dRight").pressed()) {
      trackSelected++;
      if (trackSelected > 4) trackSelected = 1;
      trackPreviewImage = loadImage("UI/track"+trackSelected+".png");
      menuCooldown = int(frameRate * 0.333);
    } else if (stick.getButton("dLeft").pressed()) {
      trackSelected--;
      if (trackSelected < 1) trackSelected = 4;
      trackPreviewImage = loadImage("UI/track"+trackSelected+".png");
      menuCooldown = int(frameRate * 0.333);
    } else if (stick.getButton("Y").pressed()) {
      scoresShown = !scoresShown;
      menuCooldown = int(frameRate);
    } else if (stick.getButton("Start").pressed() && !scoresShown) {
      menuCooldown = int(frameRate*0.333);
      scoresShown = false;
      loadMap();
    } 
    
  }
  
}

// Handles Controller input during gameplay
public void processUserGameInput() {
  
  // If player is holding both triggers, braking takes priority
  // The car will always try to move towards a target speed and the triggers just affect what the target is.
  // Full braking is -50, max acceleration is whatever the car's top speed is, nothing pressed means 0 is the target
  // If full lock turning, the target is 75% of the throttle input's target speed
  accelInput = stick.getSlider("RT").getValue();
  brakeInput= stick.getSlider("LT").getValue();
  boolean isAccelerating = accelInput > -1 ? true : false;
  boolean isBraking = brakeInput > -1 ? true : false;
  float turnInput = stick.getSlider("L Stick").getValue()*playerTurnRate[carSelected];
  
  if (isBraking) { 
    // Player is braking
    targetSpeed = playerMaxReverseSpeed*(stick.getSlider("LT").getValue()+1);
    playerSpeed = lerp(playerSpeed, targetSpeed, playerAccelRate[carSelected]*0.5);
  } else if (isAccelerating) {
    // Player is accelerating
    targetSpeed = playerMaxSpeed[carSelected]*stick.getSlider("RT").getValue();
    targetSpeed -= targetSpeed*(abs(turnInput)/playerTurnRate[carSelected])*0.25;
    playerSpeed = lerp(playerSpeed, targetSpeed, playerAccelRate[carSelected]*0.5);
  } else {
    // Natural deceleration here, no controls pressed
    playerSpeed = lerp(playerSpeed, 0, playerDecelRate[carSelected]);
    if (playerSpeed < 0 && playerSpeed > -2) playerSpeed = 0;
    if (playerSpeed > 0 && playerSpeed < 2) playerSpeed = 0;
  }
  
  // 'Dead zones' - My controller doesn't centre properly, so I've had to set anything under 5% input to 0.
  if (turnInput < 0.05 && turnInput > -0.05) {turnInput = 0;}
  float speedPenalty = (playerSpeed/playerMaxSpeed[carSelected]);
  
  // Slower turning if the player is accelerating
  if (isAccelerating) {turnInput *= 0.5;}
  
  // Apply the turning to the player's direction
  playerDirection += turnInput*speedPenalty;
  playerSprite.setRot(playerDirection);
  playerSprite.setSpeed(playerSpeed,playerDirection);
  
  if (stick.getButton("Start").pressed() && menuCooldown == 0) {
    gameState = 0;
    playerSprite.setVelXY(0, 0);
    playerSpeed = 0;
    menuCooldown = int(frameRate);
  } else if (stick.getButton("Select").pressed() && menuCooldown == 0) {
    playerSprite.setVelXY(0, 0);
    playerSpeed = 0;
    initGameStart();
    gameState = 1;
    menuCooldown = int(frameRate);
  }
}
