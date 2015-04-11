//
//  AMBScoreKeeper.m
//  CharacterTests
//
//  Created by Alex Taylor on 2014-09-05.
//  Copyright (c) 2014 Alex Taylor. All rights reserved.
//

#import "AMBScoreKeeper.h"
#import "AMBLevelScene.h" 
#import "AMBPatient.h"
#import "SKTUtils.h" // for RandomFloatRange


const int SCORE_LABEL_SPACING = 30; // vertical spacing between score messages (e.g. "Safe DRiving bonus")

#pragma mark SCORING CONSTANTS
const int SCORE_PATIENT_SEVERITY_1 =                100000;
const int SCORE_PATIENT_SEVERITY_2 =                200000;
const int SCORE_PATIENT_SEVERITY_3 =                300000;
const int SCORE_PATIENT_TTL_BONUS =                 50000;
const int SCORE_SAFE_DRIVING_BONUS =                30000;
const int SCORE_CARS_HIT_MULTIPLIER =               SCORE_SAFE_DRIVING_BONUS / 5; // max number of cars you can hit, then you get a zero safe driving
const int SCORE_END_ALL_PATIENTS_DELIVERED_BONUS =  10000;



typedef enum {
    ScoreKeeperNotificationFuelEmpty,
    ScoreKeeperNotificationFuelUp,
    ScoreKeeperNotificationInvincibility,
    ScoreKeeperNotificationPatientDelivered,
    ScoreKeeperNotificationPatientDied,
    ScoreKeeperNotificationTimeOut
} ScoreKeeperNotifications;


@interface AMBScoreKeeper ()

@property NSInteger carsHit;
@property NSMutableArray *messages; // keeps track of the score messages, for positioning on screen.
@property NSNumberFormatter *formatter; // for adding the commas

@end

@implementation AMBScoreKeeper

/**
 Instantiates a ScoreKeeper instance, and ensures that only one instance can be created.
 */
+ (AMBScoreKeeper *)sharedInstance {
    static AMBScoreKeeper *_sharedInstance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedInstance = [[AMBScoreKeeper alloc]init];
    });
    
    return _sharedInstance;
}

- (id)init {
    if (self = [super init]) {
        /* Initialize anything needed for game logic */
        _score = 0;
        _patientsDelivered = 0;
        _carsHit = 0;
        _messages = [NSMutableArray array];

        _formatter = [[NSNumberFormatter alloc]init];
        [_formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    }
    
   return self;
}



-(SKSpriteNode *)createNotificationAtPos:(CGPoint)pos {

    CGFloat sizeMult = (self.scene.size.width * 0.85) / sNotificationFuelEmpty.size.width; // this assumes that all notifications are the same size

    _notificationNode = [SKSpriteNode spriteNodeWithColor:[SKColor whiteColor] size:CGSizeMake(50, 50)];
    _notificationNode.size = CGSizeMake(sNotificationFuelEmpty.size.width * sizeMult, sNotificationFuelEmpty.size.height * sizeMult);
    _notificationNode.zPosition = 1000;
    _notificationNode.alpha = 0;

    
    return _notificationNode;
}

- (NSString *)scoreDisplay:(NSInteger)score {
    
    NSString *stringWithCommas = [_formatter stringFromNumber:[NSNumber numberWithInteger:score]];
    
    return stringWithCommas;
}

- (SKLabelNode *)createScoreLabelWithPoints:(NSInteger)points atPos:(CGPoint)position {
    
    _labelScore = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Bold"];
    _labelScore.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    _labelScore.text = [self scoreDisplay:_score];
    _labelScore.fontColor = [SKColor yellowColor];
    _labelScore.fontSize = 70;
    _labelScore.position = position;
    

    
    _labelScore.zPosition = 999;
    
    return _labelScore;
}

- (SKLabelNode *)createScoreUpdateLabelAtPos:(CGPoint)position {
    _labelScoreUpdate = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext"];
    _labelScoreUpdate.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    _labelScoreUpdate.text = @"..";
    _labelScoreUpdate.fontSize = 25;
    _labelScoreUpdate.fontColor = [SKColor yellowColor];
    _labelScoreUpdate.position = position;
    _labelScoreUpdate.zPosition = 999;
    _labelScoreUpdate.alpha = 0;
    
    _labelScoreUpdate.userData = [NSMutableDictionary dictionaryWithObject:[NSValue valueWithCGPoint:position] forKey:@"originalPos"];
    
    return _labelScoreUpdate;
}

- (void) updateScoreLabelWithPoints:(NSInteger)points {
    _labelScore.text = [self scoreDisplay:_score];
}

- (void)update {
    
}


- (void) updateScore:(NSInteger)points withMessage:(NSString *)message {
    _score += points;
    
    [self updateScoreLabelWithPoints:_score];
    
    [_labelScore runAction:sScoreLabelPop];
    
    if (message) {
        SKLabelNode *label = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Regular"];
        label.fontSize = 25;
        label.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
        label.fontColor = [SKColor yellowColor];
        label.alpha = 0; // start hidden
        
        NSString *pointsCommas = [self scoreDisplay:points];
        
        NSUInteger mCount = [_messages count];
        
        [label setText:[NSString stringWithFormat:@"%@: +%@", message, pointsCommas]];
        
        [_messages addObject:label];
        
        label.position = CGPointMake(_scene.size.width/2 - 120, _scene.size.height/2 - 170 - mCount * SCORE_LABEL_SPACING);

        
        [_scene addChild:label];
        [label runAction:sScoreMessageActions[mCount] completion:^(void){ [_messages removeObject:label]; }];
        
    }

}




#pragma mark Scoring Events
- (void)handleEventDeliveredPatient:(AMBPatient *)patient {
    NSMutableDictionary *userData = patient.userData;
    NSTimeInterval timeRemaining = [patient getPatientTTL];
    NSTimeInterval timeToLive = [[userData valueForKey:@"timeToLive"] doubleValue];
    PatientSeverity severity = [[userData valueForKey:@"severity"] intValue];
    
    _patientsDelivered += 1;
    
    int PATIENT_DELIVERED_BASE_SCORE = SCORE_PATIENT_SEVERITY_1; // init to default amount
    
    switch (severity) {
        case LevelOne:
            PATIENT_DELIVERED_BASE_SCORE = SCORE_PATIENT_SEVERITY_1;
            break;
            
        case LevelTwo:
            PATIENT_DELIVERED_BASE_SCORE = SCORE_PATIENT_SEVERITY_2;
            break;
            
        case LevelThree:
            PATIENT_DELIVERED_BASE_SCORE = SCORE_PATIENT_SEVERITY_3;
            break;
    }
    
    // define the formula for applying points
    NSInteger netPoints = PATIENT_DELIVERED_BASE_SCORE;
    NSInteger patientTTLpoints;
    
    CGFloat timeBonusRatio = timeRemaining / timeToLive;
    
    if (timeBonusRatio > 0.75) {
        patientTTLpoints = SCORE_PATIENT_TTL_BONUS;
    } else if (timeBonusRatio > 0.4 && timeBonusRatio < 0.75) {
        patientTTLpoints = SCORE_PATIENT_TTL_BONUS / 10;
    } else if (timeBonusRatio < 0.25) {
        patientTTLpoints = SCORE_PATIENT_TTL_BONUS / 100;
    }
    
    NSInteger safeDriving = SCORE_SAFE_DRIVING_BONUS - ( _carsHit * SCORE_CARS_HIT_MULTIPLIER );
    
    [self updateScore:netPoints withMessage:@"Patient Delivered"];
    [self updateScore:patientTTLpoints withMessage:@"Time Bonus"];
    [self updateScore:safeDriving withMessage:@"Safe Driving Bonus"];

    [self showNotification:ScoreKeeperNotificationPatientDelivered];
    
    if (_patientsDelivered == _patientsTotal) {
        [_scene performSelector:@selector(allPatientsDelivered)];
    }

    
    _carsHit = 0;
    
}

- (void)handleEventCarHit {
    _carsHit += 1;
}

- (void)handleEventOutOfFuel {
    [self showNotification:ScoreKeeperNotificationFuelEmpty];
}

- (void)handleEventOutOfTime {
    [self showNotification:ScoreKeeperNotificationTimeOut];
}

- (void)handleEventInvincible {
    [self showNotification:ScoreKeeperNotificationInvincibility];
}

-(void)handleEventSavedEveryone {
    // do nothing just yet
}


- (void)showNotification:(ScoreKeeperNotifications)notification {
    switch (notification) {
        case ScoreKeeperNotificationFuelEmpty:
            _notificationNode.texture = sNotificationFuelEmpty;
            break;

        case ScoreKeeperNotificationFuelUp:
            _notificationNode.texture = sNotificationFuelUp;
            break;
            
        case ScoreKeeperNotificationInvincibility:
            _notificationNode.texture = sNotificationInvincibility;
            break;
            
        case ScoreKeeperNotificationPatientDelivered:
            _notificationNode.texture = sNotificationPatientDelivered;
            break;
            
        case ScoreKeeperNotificationPatientDied:
            _notificationNode.texture = sNotificationPatientDied;
            break;
            
        case ScoreKeeperNotificationTimeOut:
            _notificationNode.texture = sNotificationTimeOut;
            break;
            
    }
    
    [_notificationNode runAction:sNotificationSequence];
}


#pragma mark Assets
+ (void)loadSharedAssets {
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        SKTextureAtlas *notifications = [SKTextureAtlas atlasNamed:@"notifications"];
        
        sNotificationFuelEmpty = [notifications textureNamed:@"notification_fuel-empty"];
        sNotificationFuelUp = [notifications textureNamed:@"notification_fuel-up"];
        sNotificationInvincibility = [notifications textureNamed:@"notification_invincibility"];
        sNotificationPatientDelivered = [notifications textureNamed:@"notification_patient-delivered"];
        sNotificationPatientDied = [notifications textureNamed:@"notification_patient-died"];
        sNotificationTimeOut = [notifications textureNamed:@"notification_time-out"];
        
        sScoreLabelPop = [SKAction sequence:@[[SKAction scaleTo:1.25 duration:0.15],[SKAction scaleTo:1.0 duration:0.075]]];
        
        sNotificationSequence = [SKAction sequence:@[[SKAction fadeInWithDuration:0.15], [SKAction waitForDuration:2.5], [SKAction fadeOutWithDuration:0.15]]];
        
        // set up score message actions, to allow the "stacking" of score messages without dynamically creating actions.
        sScoreMessageActions = [NSArray arrayWithObjects:
                                [SKAction sequence:@[
                                    [SKAction waitForDuration:0.15], [SKAction fadeInWithDuration:0.15], [SKAction waitForDuration:4.0], [SKAction fadeOutWithDuration:0.5]]],

                                [SKAction sequence:@[
                                    [SKAction waitForDuration:0.3], [SKAction fadeInWithDuration:0.15], [SKAction waitForDuration:4.0], [SKAction fadeOutWithDuration:0.5]]],
                                
                                [SKAction sequence:@[
                                    [SKAction waitForDuration:0.45], [SKAction fadeInWithDuration:0.15], [SKAction waitForDuration:4.0], [SKAction fadeOutWithDuration:0.5]]],

                                [SKAction sequence:@[
                                    [SKAction waitForDuration:0.6], [SKAction fadeInWithDuration:0.15], [SKAction waitForDuration:4.0], [SKAction fadeOutWithDuration:0.5]]],
                                
                                nil];
        
    });
    
}

static SKTexture *sNotificationFuelEmpty = nil;
static SKTexture *sNotificationFuelUp = nil;
static SKTexture *sNotificationInvincibility = nil;
static SKTexture *sNotificationPatientDelivered = nil;
static SKTexture *sNotificationPatientDied = nil;
static SKTexture *sNotificationTimeOut = nil;
static SKAction *sNotificationSequence = nil;
static SKAction *sScoreLabelPop = nil;
static NSArray *sScoreMessageActions = nil;


@end
