//
//  AMBTrafficVehicle.m
//  CharacterTests
//
//  Created by Alex Taylor on 2014-11-20.
//  Copyright (c) 2014 Alex Taylor. All rights reserved.
//

#import "AMBTrafficVehicle.h"
#import "AMBTrafficVehicleState.h"
#import "SKTUtils.h"



static const int tailgateZoneMultiplier = 2; // the zone in which tailgating is enabled is the vehicle's height multiplied by this value.
static const CGFloat resumeMovementDelayLower = 0.5; // if the vehicle is stopped, a random delay between when the blocking vehicle starts moving and when this vehicle starts moving.
static const CGFloat resumeMovementDelayUpper = 1.25;


@interface AMBTrafficVehicle ()

@property CGFloat targetSpeed;
@property AMBMovingCharacter *blockingVehicle; // the vehicle in front of this vechicle which is preventing it from moving. if this vehicle is stopped, blockingVehicle will be checked to determine when it's OK to begin moving again.
@property BOOL isAtIntersection; // YES if this vehicle just entered an intersection


@property AMBTrafficVehicleState *currentState;



@end

@implementation AMBTrafficVehicle


- (instancetype)initWithTexture:(SKTexture *)texture {
    
    if (self = [super initWithTexture:texture]) {
        // set constants
        self.speedPointsPerSec = 600;
        self.pivotSpeed = 0;
        
        self.accelTimeSeconds = 0.75;
        self.decelTimeSeconds = 0.35;
        
        
    }
    return self;
}


+ (AMBTrafficVehicle *)createVehicle:(VehicleType)type withSpeed:(VehicleSpeed)speed atPoint:(CGPoint)point withRotation:(CGFloat)rotation shouldTurnAtIntersections:(BOOL)shouldTurn {
    
    AMBTrafficVehicle *vehicle = [[AMBTrafficVehicle alloc]initWithTexture:sVehicleType1Texture];
    
    vehicle.shouldTurnAtIntersections = shouldTurn;
    vehicle.speedPointsPerSec = speed * speedMultiplier;
    vehicle.nativeSpeed = vehicle.speedPointsPerSec; // store the native speed so we can refer to it later
    vehicle.position = point;
    vehicle.zRotation = rotation;
    vehicle.direction = CGPointForAngle(rotation);
    vehicle.name = @"traffic"; // for grouped enumeration
    
    // physics
    vehicle.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:vehicle.size];
    vehicle.physicsBody.categoryBitMask = categoryTraffic;
    vehicle.physicsBody.collisionBitMask = 0;
//    vehicle.physicsBody.contactTestBitMask = 0;
    
    vehicle.collisionZoneTailgating = [SKSpriteNode spriteNodeWithColor:[SKColor yellowColor] size:CGSizeMake(vehicle.size.width * tailgateZoneMultiplier, vehicle.size.height)]; // the coordinates are based on the node being oriented to the right
    vehicle.collisionZoneTailgating.name = @"trafficVehicleCollisionZone";
    vehicle.collisionZoneTailgating.zPosition = -2;
    vehicle.collisionZoneTailgating.position = CGPointMake(vehicle.size.width/2 + vehicle.collisionZoneTailgating.size.width/2 + 2, 0); // put the collision zone out in front; add two pixels to prevent the collision from registering
    vehicle.collisionZoneTailgating.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:vehicle.collisionZoneTailgating.size];
    vehicle.collisionZoneTailgating.physicsBody.categoryBitMask = categoryTrafficCollisionZone;
    vehicle.collisionZoneTailgating.physicsBody.collisionBitMask = 0;
    vehicle.collisionZoneTailgating.physicsBody.contactTestBitMask = categoryPlayer | categoryTraffic;
    
    vehicle.collisionZoneStopping = [SKSpriteNode spriteNodeWithColor:[SKColor redColor] size:CGSizeMake(vehicle.size.width * tailgateZoneMultiplier*0.4, vehicle.size.height)];
    vehicle.collisionZoneStopping.name = @"trafficVehicleStoppingZone";
    vehicle.collisionZoneStopping.zPosition = -1;
    vehicle.collisionZoneStopping.position = CGPointMake(vehicle.size.width/2 + vehicle.collisionZoneStopping.size.width/2 + 2, 0);
    vehicle.collisionZoneStopping.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:vehicle.collisionZoneStopping.size];
    vehicle.collisionZoneStopping.physicsBody.categoryBitMask = categoryTrafficStoppingZone;
    vehicle.collisionZoneStopping.physicsBody.collisionBitMask = 0;
    vehicle.collisionZoneStopping.physicsBody.contactTestBitMask = categoryPlayer | categoryTraffic;
    
    
    [vehicle addChild:vehicle.collisionZoneTailgating];
    [vehicle addChild:vehicle.collisionZoneStopping];
    
    vehicle.collisionZoneStopping.hidden = YES;
    vehicle.collisionZoneTailgating.hidden = YES;

    // enter the initial state
    vehicle.currentState = [AMBTrafficVehicleIsDrivingStraight sharedInstance];
    [vehicle.currentState enterState:vehicle];
    
    return vehicle;
}



#pragma mark Other
- (void)changeState:(VehicleState)newState {
    _state = newState;
    
    switch (_state) {
        case VehicleIsStopped:
            [self stopMovingWithDecelTime:self.decelTimeSeconds];
            break;
            
            
        case VehicleIsDrivingStraight:
            if (!self.isMoving) {
                [self startMoving];
                _blockingVehicle = nil; // clear the blocking vehicle
            }
            break;
            
            
        case VehicleCanTurn:
            //
            break;
        
            
        case VehicleIsTailgating:
            // 
            break;
            
            
        case VehicleIsAdjustingSpeed:
            [self adjustSpeedToTarget:_targetSpeed];
            break;
            
    }
}

- (void)beganCollision:(SKPhysicsContact *)contact {
    AMBTrafficVehicleState *newState = [_currentState beganCollision:contact  context:self];
    
    if (newState) {
        _currentState = newState;
        [_currentState enterState:self];
    }
}

- (void)endedCollision:(SKPhysicsContact *)contact {
    AMBTrafficVehicleState *newState = [_currentState endedCollision:contact  context:self];
    
    if (newState) {
        _currentState = newState;
        [_currentState enterState:self];
        
    }

}

- (void)collidedWith:(SKPhysicsBody *)other victimNodeName:(NSString *)name {
    
    AMBMovingCharacter *node = (AMBMovingCharacter *)other.node;
    
    if ([name isEqualToString:@"trafficVehicleCollisionZone"]) {
        NSLog(@"[%@] %@ collisionZone", self.name, NSStringFromSelector(_cmd));
        if (node.isMoving) {
            if ([node isKindOfClass:[AMBTrafficVehicle class]]) {
                NSLog(@"[%@] %@ collisionZone | encountered traffic vehicle; state -> VehicleIsAdjustingSpeed", self.name, NSStringFromSelector(_cmd));
                _targetSpeed = node.speedPointsPerSec * 0.75;
                [self changeState:VehicleIsAdjustingSpeed];
            } else {
                NSLog(@"[%@] %@ collisionZone | encountered non-traffic entity; speed -> 80%% native", self.name, NSStringFromSelector(_cmd));
                _targetSpeed = self.speedPointsPerSec * 0.8;
                [self changeState:VehicleIsAdjustingSpeed];
            }
            
        } else {
            NSLog(@"[%@] %@ collisionZone | encountered stopped node; state -> VehicleIsStopped", self.name, NSStringFromSelector(_cmd));
            [self changeState:VehicleIsStopped];
            _blockingVehicle = node;
        }
        
    } else if ([name isEqualToString:@"trafficVehicleStoppingZone"]) {
        NSLog(@"[%@] %@ stoppingZone | state -> VehicleIsStopped; previous speed: %1.5f", self.name, NSStringFromSelector(_cmd), self.speedPointsPerSec);
        [self changeState:VehicleIsStopped]; // screech to a halt if anything comes up in this zone
        _blockingVehicle = node;
    }
    
}

- (void)endedContactWith:(SKPhysicsBody *)other victimNodeName:(NSString *)name {

    AMBMovingCharacter *node = (AMBMovingCharacter *)other.node;
    
    if (_state == VehicleIsAdjustingSpeed) {
        if ([name isEqualToString:@"trafficVehicleCollisionZone"]) {
            if ([node isKindOfClass:[AMBTrafficVehicle class]]) {
                NSLog(@"[%@] %@ collisionZone | AdjustSpeed to match; targetSpeed: %1.5f", self.name, NSStringFromSelector(_cmd), node.speedPointsPerSec);
                _targetSpeed = self.nativeSpeed;

            } else {
                NSLog(@"[%@] %@ collisionZone | AdjustSpeed to native; targetSpeed: %1.5f", self.name, NSStringFromSelector(_cmd), self.nativeSpeed);
                _targetSpeed = self.nativeSpeed; // revert to native speed if we're not matching
            }

            [self removeActionForKey:@"adjustSpeed"];
            [self changeState:VehicleIsAdjustingSpeed];

            NSLog(@"[%@] %@ collisionZone | state VehicleIsDrivingStraight", self.name, NSStringFromSelector(_cmd));
            [self changeState:VehicleIsDrivingStraight];

        }
    } else if (_state == VehicleIsStopped) {
        if ([name isEqualToString:@"trafficVehicleCollisionZone"]) {

            if ([node isKindOfClass:[AMBTrafficVehicle class]]) {
                NSLog(@"[%@] %@ collisionZone | setting speed to target node speed: %1.f", self.name, NSStringFromSelector(_cmd), node.speedPointsPerSec);
                self.speedPointsPerSec = self.nativeSpeed;
            } else {
                NSLog(@"[%@] %@ collisionZone | setting speed to native speed: %1.5f", self.name, NSStringFromSelector(_cmd), self.nativeSpeed);
                self.speedPointsPerSec = self.nativeSpeed;
            }

            NSLog(@"[%@] %@ collisionZone | state VehicleStopped -> VehicleIsDrivingStraight; speed %1.5f", self.name, NSStringFromSelector(_cmd),self.speedPointsPerSec);
            [self runAction:[SKAction waitForDuration:RandomFloatRange(resumeMovementDelayLower, resumeMovementDelayUpper)]
                 completion:^(void){
                     [self changeState:VehicleIsDrivingStraight];
                 }];
        }
    }
}

- (void)updateWithTimeSinceLastUpdate:(CFTimeInterval)delta {
    // the superclass handles moving the sprite
    [super updateWithTimeSinceLastUpdate:delta];

    // state
    AMBTrafficVehicleState *newState = [_currentState updateWithTimeSinceLastUpdate:delta context:self];
    
    if (newState) {
        _currentState = newState;
        [_currentState enterState:self];
    }
    
    
}

#pragma mark Assets
+ (void)loadSharedAssets {
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
    
        // thought I needed to preload this, but it seems to use the same instance as other invocations (e.g. in powerup)
        SKTextureAtlas *gameObjectSprites = [SKTextureAtlas atlasNamed:@"GameObjectSprites"];
        
        sVehicleType1Texture = [gameObjectSprites textureNamed:@"traffic"];

    });
    
    
}

static SKTexture *sVehicleType1Texture = nil;
- (SKTexture *)vehicleType1Texture {
    return sVehicleType1Texture;
}

@end


