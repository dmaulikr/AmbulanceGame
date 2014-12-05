//
//  XXXCharacter.m
//  CharacterTests
//
//  Created by Alex Taylor on 2014-07-06.
//  Copyright (c) 2014 Alex Taylor. All rights reserved.
//
#define SK_DEGREES_TO_RADIANS(__ANGLE__) ((__ANGLE__) * 0.01745329252f) // PI / 180
#define SK_RADIANS_TO_DEGREES(__ANGLE__) ((__ANGLE__) * 57.29577951f) // PI * 180

#import "AMBPlayer.h"
#import "AMBLevelScene.h"
#import "AMBScoreKeeper.h"
#import "SKTUtils.h"

static CGFloat FUEL_TIMER_INCREMENT = 10; // every x seconds, the fuel gets decremented


@interface AMBPlayer ()

//@property NSTimeInterval sceneDelta;


@property SKSpriteNode *sirens;
@property SKAction *sirensOn;
@property AMBScoreKeeper *scoreKeeper;
@property NSTimeInterval fuelTimer; // times when the fuel started being depleted by startMoving

@end

@implementation AMBPlayer


- (instancetype) init {
    self = [super initWithImageNamed:@"asset_ambulance_20140609"];
    
    // set constants
    self.speedPointsPerSec = 600;
    self.pivotSpeed = 0;

    self.accelTimeSeconds = 0.75;
    self.decelTimeSeconds = 0.35;
    
    self.name = @"player";
    self.size = CGSizeMake(self.size.width*0.75,self.size.height*0.75);
    self.anchorPoint = CGPointMake(0.35, 0.5);
    self.zRotation = DegreesToRadians(90);
    self.zPosition = 100;
    
    // physics (for collisions)
    self.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:self.size];
    self.physicsBody.categoryBitMask = categoryPlayer;
    self.physicsBody.contactTestBitMask = categoryHospital | categoryPatient | categoryTraffic;
    self.physicsBody.collisionBitMask = 0;

    
    self.direction = CGPointMake(0, 1); // default direction, move up
    
    _state = AmbulanceIsEmpty; // set initial ambulance state
    
    // sirens! wee-ooh, wee-oh, wee-ooh...
    SKTextureAtlas *sirenAtlas = [SKTextureAtlas atlasNamed:@"sirens"];
    SKTexture *sirenLeft = [sirenAtlas textureNamed:@"amulance_sirens_left.png"];
    SKTexture *sirenRight = [sirenAtlas textureNamed:@"amulance_sirens_right.png"];
    _sirensOn = [SKAction animateWithTextures:@[sirenLeft, sirenRight] timePerFrame:0.8];

    _sirens = [SKSpriteNode spriteNodeWithTexture:sirenLeft];
    _sirens.hidden = YES;
    _sirens.position = CGPointMake(25, 0);
    _sirens.size = CGSizeMake(self.size.width*0.75,self.size.height*0.75);

    [self addChild:_sirens];
    
    _scoreKeeper = [AMBScoreKeeper sharedInstance]; // hook up the shared instance of the score keeper so we can talk to it
    
    _fuel = 3;
    
    return self;
}

- (void)updateWithTimeSinceLastUpdate:(CFTimeInterval)delta {
    // the superclass handles moving the sprite
    [super updateWithTimeSinceLastUpdate:delta];

    AMBLevelScene *__weak owningScene = [self characterScene]; // declare a reference to the scene as weak, to prevent a reference cycle. Inspired by animationDidComplete in Adventure.
    
    if (self.requestedMoveEvent && self.levelScene.sceneLastUpdate - self.levelScene.lastKeyPress < TURN_BUFFER) {
        [self authorizeMoveEvent:self.requestedMoveEventDegrees];
    }
    
    // update the patient timer
    if (self.patient) {
        NSTimeInterval ttl = [self.patient getPatientTTL];
        owningScene.patientTimeToLive.text = [NSString stringWithFormat:@"PATIENT: %1.1f",ttl];
    }
    
    // update fuel if we're moving
    if (self.isMoving) {
        NSTimeInterval now = CACurrentMediaTime();
        if (now - _fuelTimer > FUEL_TIMER_INCREMENT) {
            _fuelTimer = now;
            _fuel--; // decrement fuel
            NSLog(@"fuel is now %f",_fuel);

            
            owningScene.fuelStatus.text = [NSString stringWithFormat:@"FUEL: %1.0f/3",_fuel];
            
            if (_fuel < 1) {
                [self stopMoving];
                SKLabelNode *gameOver = [SKLabelNode labelNodeWithFontNamed:@"Impact"];
                gameOver.text = @"GAME OVER!";
                gameOver.fontColor = [SKColor yellowColor];
                gameOver.zPosition = 1000;
                gameOver.fontSize = 80;
                [owningScene addChild:gameOver];
                
                
                
            }
            
        }
    }
}


#pragma mark Game Logic
-(void)changeState:(AmbulanceState)newState {
    _state = newState;

    AMBLevelScene *__weak owningScene = [self characterScene]; // declare a reference to the scene as weak, to prevent a reference cycle. Inspired by animationDidComplete in Adventure.
    
    switch (_state) {
        case AmbulanceIsEmpty:
            [_sirens removeActionForKey:@"sirensOn"];
            _sirens.hidden = YES;
            
            owningScene.patientTimeToLive.text = @"PATIENT: --";
            
            
            break;
            
        case AmbulanceIsOccupied:
            [_sirens runAction:[SKAction repeatActionForever:_sirensOn] withKey:@"sirensOn"];
            _sirens.hidden = NO;
            [owningScene.indicator removeTarget:self.patient];
            break;
    }
}


-(BOOL)loadPatient:(AMBPatient *)patient {
    // loads a given patient into the ambulance. returns true on success, false on failure (if the ambulance was already occupied)
    
    if (_state == AmbulanceIsEmpty) {
        [patient changeState:PatientIsEnRoute];
        _patient = patient; // load the patient into the ambulance
        [self changeState:AmbulanceIsOccupied];
        return YES;
    }
    
    return NO;
}

-(BOOL)unloadPatient {
    // unloads a patient from the ambulance (if there is one)
    if (_patient) {
        [self changeState:AmbulanceIsEmpty];
        [_patient changeState:PatientIsDelivered];
        _patient = nil;
        return YES;
    }
    
    return NO;
}

- (void)collidedWith:(SKPhysicsBody *)other victimNodeName:(NSString *)name {
    
    switch (other.categoryBitMask) {
        case categoryPatient:
            [self loadPatient:(AMBPatient *)other.node];
            break;
            
        case categoryTraffic:
            
        case categoryHospital:
            if (self.patient) {
                [_scoreKeeper scoreEventDeliveredPatient:self.patient];
                [self unloadPatient];
            }
            break;
            
    }
}


- (void)startMoving {
    [super startMoving];
    
    // update fuel counter
    _fuelTimer = CACurrentMediaTime();
    NSLog(@"started fuel timer");
}


@end
