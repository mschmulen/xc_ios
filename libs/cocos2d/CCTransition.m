/*
 * cocos2d for iPhone: http://www.cocos2d-iphone.org
 *
 * Copyright (c) 2008-2010 Ricardo Quesada
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */



#import "CCTransition.h"
#import "CCNode.h"
#import "CCDirector.h"
#import "CCActionInterval.h"
#import "CCActionInstant.h"
#import "CCActionCamera.h"
#import "CCLayer.h"
#import "CCCamera.h"
#import "CCActionTiledGrid.h"
#import "CCActionEase.h"
#import "CCRenderTexture.h"
#import "Support/CGPointExtension.h"

#import <Availability.h>
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
#import "Platforms/iOS/CCTouchDispatcher.h"
#elif defined(__MAC_OS_X_VERSION_MAX_ALLOWED)
#import "Platforms/Mac/CCEventDispatcher.h"
#endif

enum {
	kSceneFade = 0xFADEFADE,
};

@interface CCTransitionScene (Private)
-(void) sceneOrder;
- (void)setNewScene:(ccTime)dt;
@end

@implementation CCTransitionScene
+(id) transitionWithDuration:(ccTime) t scene:(CCScene*)s
{
	return [[[self alloc] initWithDuration:t scene:s] autorelease];
}

-(id) initWithDuration:(ccTime) t scene:(CCScene*)s
{
	NSAssert( s != nil, @"Argument scene must be non-nil");
	
	if( (self=[super init]) ) {
	
		duration = t;
		
		// retain
		inScene = [s retain];
		outScene = [[CCDirector sharedDirector] runningScene];
		[outScene retain];
		
		NSAssert( inScene != outScene, @"Incoming scene must be different from the outgoing scene" );

		// disable events while transitions
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
		[[CCTouchDispatcher sharedDispatcher] setDispatchEvents: NO];
#elif defined(__MAC_OS_X_VERSION_MAX_ALLOWED)
		[[CCEventDispatcher sharedDispatcher] setDispatchEvents: NO];
#endif

		[self sceneOrder];
	}
	return self;
}
-(void) sceneOrder
{
	inSceneOnTop = YES;
}

-(void) draw
{
	if( inSceneOnTop ) {
		[outScene visit];
		[inScene visit];
	} else {
		[inScene visit];
		[outScene visit];
	}
}

-(void) finish
{
	/* clean up */	
	[inScene setVisible:YES];
	[inScene setPosition:ccp(0,0)];
	[inScene setScale:1.0f];
	[inScene setRotation:0.0f];
	[inScene.camera restore];
	
	[outScene setVisible:NO];
	[outScene setPosition:ccp(0,0)];
	[outScene setScale:1.0f];
	[outScene setRotation:0.0f];
	[outScene.camera restore];
	
	[self schedule:@selector(setNewScene:) interval:0];
}

-(void) setNewScene: (ccTime) dt
{	
	[self unschedule:_cmd];
	
	CCDirector *director = [CCDirector sharedDirector];
	
	// Before replacing, save the "send cleanup to scene"
	sendCleanupToScene = [director sendCleanupToScene];
	
	[director replaceScene: inScene];

	// enable events while transitions
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
	[[CCTouchDispatcher sharedDispatcher] setDispatchEvents: YES];
#elif defined(__MAC_OS_X_VERSION_MAX_ALLOWED)
	[[CCEventDispatcher sharedDispatcher] setDispatchEvents: YES];
#endif
	
	// issue #267
	[outScene setVisible:YES];	
}

-(void) hideOutShowIn
{
	[inScene setVisible:YES];
	[outScene setVisible:NO];
}

// custom onEnter
-(void) onEnter
{
	[super onEnter];
	[inScene onEnter];
	// outScene should not receive the onEnter callback
}

// custom onExit
-(void) onExit
{
	[super onExit];
	[outScene onExit];

	// inScene should not receive the onExit callback
	// only the onEnterTransitionDidFinish
	[inScene onEnterTransitionDidFinish];
}

// custom cleanup
-(void) cleanup
{
	[super cleanup];
	
	if( sendCleanupToScene )
	   [outScene cleanup];
}

-(void) dealloc
{
	[inScene release];
	[outScene release];
	[super dealloc];
}
@end

//
// Oriented Transition
//
@implementation CCTransitionSceneOriented
+(id) transitionWithDuration:(ccTime) t scene:(CCScene*)s orientation:(tOrientation)o
{
	return [[[self alloc] initWithDuration:t scene:s orientation:o] autorelease];
}

-(id) initWithDuration:(ccTime) t scene:(CCScene*)s orientation:(tOrientation)o
{
	if( (self=[super initWithDuration:t scene:s]) )
		orientation = o;
	return self;
}
@end


//
// RotoZoom
//
@implementation CCTransitionRotoZoom
-(void) onEnter
{
	[super onEnter];
	
	[inScene setScale:0.001f];
	[outScene setScale:1.0f];
	
	[inScene setAnchorPoint:ccp(0.5f, 0.5f)];
	[outScene setAnchorPoint:ccp(0.5f, 0.5f)];
	
	CCActionInterval *rotozoom = [CCSequence actions: [CCSpawn actions:
								   [CCScaleBy actionWithDuration:duration/2 scale:0.001f],
								   [CCRotateBy actionWithDuration:duration/2 angle:360 *2],
								   nil],
								[CCDelayTime actionWithDuration:duration/2],
							nil];
	
	
	[outScene runAction: rotozoom];
	[inScene runAction: [CCSequence actions:
					[rotozoom reverse],
					[CCCallFunc actionWithTarget:self selector:@selector(finish)],
				  nil]];
}
@end

//
// JumpZoom
//
@implementation CCTransitionJumpZoom
-(void) onEnter
{
	[super onEnter];
	CGSize s = [[CCDirector sharedDirector] winSize];
	
	[inScene setScale:0.5f];
	[inScene setPosition:ccp( s.width,0 )];

	[inScene setAnchorPoint:ccp(0.5f, 0.5f)];
	[outScene setAnchorPoint:ccp(0.5f, 0.5f)];

	CCActionInterval *jump = [CCJumpBy actionWithDuration:duration/4 position:ccp(-s.width,0) height:s.width/4 jumps:2];
	CCActionInterval *scaleIn = [CCScaleTo actionWithDuration:duration/4 scale:1.0f];
	CCActionInterval *scaleOut = [CCScaleTo actionWithDuration:duration/4 scale:0.5f];
	
	CCActionInterval *jumpZoomOut = [CCSequence actions: scaleOut, jump, nil];
	CCActionInterval *jumpZoomIn = [CCSequence actions: jump, scaleIn, nil];
	
	CCActionInterval *delay = [CCDelayTime actionWithDuration:duration/2];
	
	[outScene runAction: jumpZoomOut];
	[inScene runAction: [CCSequence actions: delay,
								jumpZoomIn,
								[CCCallFunc actionWithTarget:self selector:@selector(finish)],
								nil] ];
}
@end

//
// MoveInL
//
@implementation CCTransitionMoveInL
-(void) onEnter
{
	[super onEnter];
	
	[self initScenes];
	
	CCActionInterval *a = [self action];

	[inScene runAction: [CCSequence actions:
						 [self easeActionWithAction:a],
						 [CCCallFunc actionWithTarget:self selector:@selector(finish)],
						 nil]
	];
	 		
}
-(CCActionInterval*) action
{
	return [CCMoveTo actionWithDuration:duration position:ccp(0,0)];
}

-(CCActionInterval*) easeActionWithAction:(CCActionInterval*)action
{
	return [CCEaseOut actionWithAction:action rate:2.0f];
//	return [EaseElasticOut actionWithAction:action period:0.4f];
}

-(void) initScenes
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	[inScene setPosition: ccp( -s.width,0) ];
}
@end

//
// MoveInR
//
@implementation CCTransitionMoveInR
-(void) initScenes
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	[inScene setPosition: ccp( s.width,0) ];
}
@end

//
// MoveInT
//
@implementation CCTransitionMoveInT
-(void) initScenes
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	[inScene setPosition: ccp( 0, s.height) ];
}
@end

//
// MoveInB
//
@implementation CCTransitionMoveInB
-(void) initScenes
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	[inScene setPosition: ccp( 0, -s.height) ];
}
@end

//
// SlideInL
//

// The adjust factor is needed to prevent issue #442
// One solution is to use DONT_RENDER_IN_SUBPIXELS images, but NO
// The other issue is that in some transitions (and I don't know why)
// the order should be reversed (In in top of Out or vice-versa).
#define ADJUST_FACTOR 0.5f
@implementation CCTransitionSlideInL
-(void) onEnter
{
	[super onEnter];

	[self initScenes];
	
	CCActionInterval *in = [self action];
	CCActionInterval *out = [self action];

	id inAction = [self easeActionWithAction:in];
	id outAction = [CCSequence actions:
					[self easeActionWithAction:out],
					[CCCallFunc actionWithTarget:self selector:@selector(finish)],
					nil];
	
	[inScene runAction: inAction];
	[outScene runAction: outAction];
}
-(void) sceneOrder
{
	inSceneOnTop = NO;
}
-(void) initScenes
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	[inScene setPosition: ccp( -(s.width-ADJUST_FACTOR),0) ];
}
-(CCActionInterval*) action
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	return [CCMoveBy actionWithDuration:duration position:ccp(s.width-ADJUST_FACTOR,0)];
}

-(CCActionInterval*) easeActionWithAction:(CCActionInterval*)action
{
	return [CCEaseOut actionWithAction:action rate:2.0f];
//	return [EaseElasticOut actionWithAction:action period:0.4f];
}

@end

//
// SlideInR
//
@implementation CCTransitionSlideInR
-(void) sceneOrder
{
	inSceneOnTop = YES;
}
-(void) initScenes
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	[inScene setPosition: ccp( s.width-ADJUST_FACTOR,0) ];
}

-(CCActionInterval*) action
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	return [CCMoveBy actionWithDuration:duration position:ccp(-(s.width-ADJUST_FACTOR),0)];
}

@end

//
// SlideInT
//
@implementation CCTransitionSlideInT
-(void) sceneOrder
{
	inSceneOnTop = NO;
}
-(void) initScenes
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	[inScene setPosition: ccp(0,s.height-ADJUST_FACTOR) ];
}

-(CCActionInterval*) action
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	return [CCMoveBy actionWithDuration:duration position:ccp(0,-(s.height-ADJUST_FACTOR))];
}

@end

//
// SlideInB
//
@implementation CCTransitionSlideInB
-(void) sceneOrder
{
	inSceneOnTop = YES;
}

-(void) initScenes
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	[inScene setPosition: ccp(0,-(s.height-ADJUST_FACTOR)) ];
}

-(CCActionInterval*) action
{
	CGSize s = [[CCDirector sharedDirector] winSize];
	return [CCMoveBy actionWithDuration:duration position:ccp(0,s.height-ADJUST_FACTOR)];
}
@end

//
// ShrinkGrow Transition
//
@implementation CCTransitionShrinkGrow
-(void) onEnter
{
	[super onEnter];
	
	[inScene setScale:0.001f];
	[outScene setScale:1.0f];

	[inScene setAnchorPoint:ccp(2/3.0f,0.5f)];
	[outScene setAnchorPoint:ccp(1/3.0f,0.5f)];	
	
	CCActionInterval *scaleOut = [CCScaleTo actionWithDuration:duration scale:0.01f];
	CCActionInterval *scaleIn = [CCScaleTo actionWithDuration:duration scale:1.0f];

	[inScene runAction: [self easeActionWithAction:scaleIn]];
	[outScene runAction: [CCSequence actions:
					[self easeActionWithAction:scaleOut],
					[CCCallFunc actionWithTarget:self selector:@selector(finish)],
					nil] ];
}
-(CCActionInterval*) easeActionWithAction:(CCActionInterval*)action
{
	return [CCEaseOut actionWithAction:action rate:2.0f];
//	return [EaseElasticOut actionWithAction:action period:0.3f];
}
@end

//
// FlipX Transition
//
@implementation CCTransitionFlipX
-(void) onEnter
{
	[super onEnter];
	
	CCActionInterval *inA, *outA;
	[inScene setVisible: NO];

	float inDeltaZ, inAngleZ;
	float outDeltaZ, outAngleZ;

	if( orientation == kOrientationRightOver ) {
		inDeltaZ = 90;
		inAngleZ = 270;
		outDeltaZ = 90;
		outAngleZ = 0;
	} else {
		inDeltaZ = -90;
		inAngleZ = 90;
		outDeltaZ = -90;
		outAngleZ = 0;
	}
		
	inA = [CCSequence actions:
		   [CCDelayTime actionWithDuration:duration/2],
		   [CCShow action],
		   [CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:inAngleZ deltaAngleZ:inDeltaZ angleX:0 deltaAngleX:0],
		   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
		   nil ];
	outA = [CCSequence actions:
			[CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:outAngleZ deltaAngleZ:outDeltaZ angleX:0 deltaAngleX:0],
			[CCHide action],
			[CCDelayTime actionWithDuration:duration/2],							
			nil ];
	
	[inScene runAction: inA];
	[outScene runAction: outA];
	
}
@end

//
// FlipY Transition
//
@implementation CCTransitionFlipY
-(void) onEnter
{
	[super onEnter];
	
	CCActionInterval *inA, *outA;
	[inScene setVisible: NO];

	float inDeltaZ, inAngleZ;
	float outDeltaZ, outAngleZ;

	if( orientation == kOrientationUpOver ) {
		inDeltaZ = 90;
		inAngleZ = 270;
		outDeltaZ = 90;
		outAngleZ = 0;
	} else {
		inDeltaZ = -90;
		inAngleZ = 90;
		outDeltaZ = -90;
		outAngleZ = 0;
	}
	inA = [CCSequence actions:
		   [CCDelayTime actionWithDuration:duration/2],
		   [CCShow action],
		   [CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:inAngleZ deltaAngleZ:inDeltaZ angleX:90 deltaAngleX:0],
		   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
		   nil ];
	outA = [CCSequence actions:
			[CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:outAngleZ deltaAngleZ:outDeltaZ angleX:90 deltaAngleX:0],
			[CCHide action],
			[CCDelayTime actionWithDuration:duration/2],							
			nil ];
	
	[inScene runAction: inA];
	[outScene runAction: outA];
	
}
@end

//
// FlipAngular Transition
//
@implementation CCTransitionFlipAngular
-(void) onEnter
{
	[super onEnter];
	
	CCActionInterval *inA, *outA;
	[inScene setVisible: NO];

	float inDeltaZ, inAngleZ;
	float outDeltaZ, outAngleZ;

	if( orientation == kOrientationRightOver ) {
		inDeltaZ = 90;
		inAngleZ = 270;
		outDeltaZ = 90;
		outAngleZ = 0;
	} else {
		inDeltaZ = -90;
		inAngleZ = 90;
		outDeltaZ = -90;
		outAngleZ = 0;
	}
	inA = [CCSequence actions:
			   [CCDelayTime actionWithDuration:duration/2],
			   [CCShow action],
			   [CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:inAngleZ deltaAngleZ:inDeltaZ angleX:-45 deltaAngleX:0],
			   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
			   nil ];
	outA = [CCSequence actions:
				[CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:outAngleZ deltaAngleZ:outDeltaZ angleX:45 deltaAngleX:0],
				[CCHide action],
				[CCDelayTime actionWithDuration:duration/2],							
				nil ];

	[inScene runAction: inA];
	[outScene runAction: outA];
}
@end

//
// ZoomFlipX Transition
//
@implementation CCTransitionZoomFlipX
-(void) onEnter
{
	[super onEnter];
	
	CCActionInterval *inA, *outA;
	[inScene setVisible: NO];
	
	float inDeltaZ, inAngleZ;
	float outDeltaZ, outAngleZ;
	
	if( orientation == kOrientationRightOver ) {
		inDeltaZ = 90;
		inAngleZ = 270;
		outDeltaZ = 90;
		outAngleZ = 0;
	} else {
		inDeltaZ = -90;
		inAngleZ = 90;
		outDeltaZ = -90;
		outAngleZ = 0;
	}
	inA = [CCSequence actions:
		   [CCDelayTime actionWithDuration:duration/2],
		   [CCSpawn actions:
			[CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:inAngleZ deltaAngleZ:inDeltaZ angleX:0 deltaAngleX:0],
			[CCScaleTo actionWithDuration:duration/2 scale:1],
			[CCShow action],
			nil],
		   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
		   nil ];
	outA = [CCSequence actions:
			[CCSpawn actions:
			 [CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:outAngleZ deltaAngleZ:outDeltaZ angleX:0 deltaAngleX:0],
			 [CCScaleTo actionWithDuration:duration/2 scale:0.5f],
			 nil],
			[CCHide action],
			[CCDelayTime actionWithDuration:duration/2],							
			nil ];
	
	inScene.scale = 0.5f;
	[inScene runAction: inA];
	[outScene runAction: outA];
}
@end

//
// ZoomFlipY Transition
//
@implementation CCTransitionZoomFlipY
-(void) onEnter
{
	[super onEnter];
	
	CCActionInterval *inA, *outA;
	[inScene setVisible: NO];
	
	float inDeltaZ, inAngleZ;
	float outDeltaZ, outAngleZ;

	if( orientation == kOrientationUpOver ) {
		inDeltaZ = 90;
		inAngleZ = 270;
		outDeltaZ = 90;
		outAngleZ = 0;
	} else {
		inDeltaZ = -90;
		inAngleZ = 90;
		outDeltaZ = -90;
		outAngleZ = 0;
	}
	
	inA = [CCSequence actions:
			   [CCDelayTime actionWithDuration:duration/2],
			   [CCSpawn actions:
				 [CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:inAngleZ deltaAngleZ:inDeltaZ angleX:90 deltaAngleX:0],
				 [CCScaleTo actionWithDuration:duration/2 scale:1],
				 [CCShow action],
				 nil],
			   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
			   nil ];
	outA = [CCSequence actions:
				[CCSpawn actions:
				 [CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:outAngleZ deltaAngleZ:outDeltaZ angleX:90 deltaAngleX:0],
				 [CCScaleTo actionWithDuration:duration/2 scale:0.5f],
				 nil],							
				[CCHide action],
				[CCDelayTime actionWithDuration:duration/2],							
				nil ];

	inScene.scale = 0.5f;
	[inScene runAction: inA];
	[outScene runAction: outA];
}
@end

//
// ZoomFlipAngular Transition
//
@implementation CCTransitionZoomFlipAngular
-(void) onEnter
{
	[super onEnter];
	
	CCActionInterval *inA, *outA;
	[inScene setVisible: NO];
	
	float inDeltaZ, inAngleZ;
	float outDeltaZ, outAngleZ;
	
	if( orientation == kOrientationRightOver ) {
		inDeltaZ = 90;
		inAngleZ = 270;
		outDeltaZ = 90;
		outAngleZ = 0;
	} else {
		inDeltaZ = -90;
		inAngleZ = 90;
		outDeltaZ = -90;
		outAngleZ = 0;
	}
		
	inA = [CCSequence actions:
		   [CCDelayTime actionWithDuration:duration/2],
		   [CCSpawn actions:
			[CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:inAngleZ deltaAngleZ:inDeltaZ angleX:-45 deltaAngleX:0],
			[CCScaleTo actionWithDuration:duration/2 scale:1],
			[CCShow action],
			nil],						   
		   [CCShow action],
		   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
		   nil ];
	outA = [CCSequence actions:
			[CCSpawn actions:
			 [CCOrbitCamera actionWithDuration: duration/2 radius: 1 deltaRadius:0 angleZ:outAngleZ deltaAngleZ:outDeltaZ angleX:45 deltaAngleX:0],
			 [CCScaleTo actionWithDuration:duration/2 scale:0.5f],
			 nil],							
			[CCHide action],
			[CCDelayTime actionWithDuration:duration/2],							
			nil ];
	
	inScene.scale = 0.5f;
	[inScene runAction: inA];
	[outScene runAction: outA];
}
@end


//
// Fade Transition
//
@implementation CCTransitionFade
+(id) transitionWithDuration:(ccTime)d scene:(CCScene*)s withColor:(ccColor3B)color
{
	return [[[self alloc] initWithDuration:d scene:s withColor:color] autorelease];
}

-(id) initWithDuration:(ccTime)d scene:(CCScene*)s withColor:(ccColor3B)aColor
{
	if( (self=[super initWithDuration:d scene:s]) ) {
		color.r = aColor.r;
		color.g = aColor.g;
		color.b = aColor.b;
	}
	
	return self;
}

-(id) initWithDuration:(ccTime)d scene:(CCScene*)s
{
	return [self initWithDuration:d scene:s withColor:ccBLACK];
}

-(void) onEnter
{
	[super onEnter];
	
	CCColorLayer *l = [CCColorLayer layerWithColor:color];
	[inScene setVisible: NO];
	
	[self addChild: l z:2 tag:kSceneFade];
	
	
	CCNode *f = [self getChildByTag:kSceneFade];
	
	CCActionInterval *a = [CCSequence actions:
						   [CCFadeIn actionWithDuration:duration/2],
						   [CCCallFunc actionWithTarget:self selector:@selector(hideOutShowIn)],
						   [CCFadeOut actionWithDuration:duration/2],
						   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
						   nil ];
	[f runAction: a];
}

-(void) onExit
{
	[super onExit];
	[self removeChildByTag:kSceneFade cleanup:NO];
}
@end


//
// Cross Fade Transition
//
@implementation CCTransitionCrossFade

-(void) draw
{
	// override draw since both scenes (textures) are rendered in 1 scene
}

-(void) onEnter
{
	[super onEnter];
	
	// create a transparent color layer
	// in which we are going to add our rendertextures
	ccColor4B  color = {0,0,0,0};
	CGSize size = [[CCDirector sharedDirector] winSize];
	CCColorLayer * layer = [CCColorLayer layerWithColor:color];
	
	// create the first render texture for inScene
	CCRenderTexture *inTexture = [CCRenderTexture renderTextureWithWidth:size.width height:size.height];
	inTexture.sprite.anchorPoint= ccp(0.5f,0.5f);
	inTexture.position = ccp(size.width/2, size.height/2);
	inTexture.anchorPoint = ccp(0.5f,0.5f);
	
	// render inScene to its texturebuffer
	[inTexture begin];
	[inScene visit];
	[inTexture end];
	
	// create the second render texture for outScene
	CCRenderTexture *outTexture = [CCRenderTexture renderTextureWithWidth:size.width height:size.height];
	outTexture.sprite.anchorPoint= ccp(0.5f,0.5f);
	outTexture.position = ccp(size.width/2, size.height/2);
	outTexture.anchorPoint = ccp(0.5f,0.5f);
	
	// render outScene to its texturebuffer
	[outTexture begin];
	[outScene visit];
	[outTexture end];
	
	// create blend functions
	
	ccBlendFunc blend1 = {GL_ONE, GL_ONE}; // inScene will lay on background and will not be used with alpha
	ccBlendFunc blend2 = {GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA}; // we are going to blend outScene via alpha 
	
	// set blendfunctions
	[inTexture.sprite setBlendFunc:blend1];
	[outTexture.sprite setBlendFunc:blend2];	
	
	// add render textures to the layer
	[layer addChild:inTexture];
	[layer addChild:outTexture];
	
	// initial opacity:
	[inTexture.sprite setOpacity:255];
	[outTexture.sprite setOpacity:255];
	
	// create the blend action
	CCActionInterval * layerAction = [CCSequence actions:
									  [CCFadeTo actionWithDuration:duration opacity:0],
									  [CCCallFunc actionWithTarget:self selector:@selector(hideOutShowIn)],
									  [CCCallFunc actionWithTarget:self selector:@selector(finish)],
									  nil ];
	
	
	// run the blend action
	[outTexture.sprite runAction: layerAction];
	
	// add the layer (which contains our two rendertextures) to the scene
	[self addChild: layer z:2 tag:kSceneFade];
}

// clean up on exit
-(void) onExit
{
	// remove our layer and release all containing objects 
	[self removeChildByTag:kSceneFade cleanup:NO];
	
	[super onExit];	
}
@end

//
// TurnOffTilesTransition
//
@implementation CCTransitionTurnOffTiles

// override addScenes, and change the order
-(void) sceneOrder
{
	inSceneOnTop = NO;
}

-(void) onEnter
{
	[super onEnter];
	CGSize s = [[CCDirector sharedDirector] winSize];
	float aspect = s.width / s.height;
	int x = 12 * aspect;
	int y = 12;
	
	id toff = [CCTurnOffTiles actionWithSize: ccg(x,y) duration:duration];
	id action = [self easeActionWithAction:toff];
	[outScene runAction: [CCSequence actions: action,
				   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
				   [CCStopGrid action],
				   nil]
	 ];

}
-(CCActionInterval*) easeActionWithAction:(CCActionInterval*)action
{
	return action;
//	return [EaseIn actionWithAction:action rate:2.0f];
}
@end

#pragma mark Split Transitions

//
// SplitCols Transition
//
@implementation CCTransitionSplitCols

-(void) onEnter
{
	[super onEnter];

	inScene.visible = NO;
	
	id split = [self action];
	id seq = [CCSequence actions:
				split,
				[CCCallFunc actionWithTarget:self selector:@selector(hideOutShowIn)],
				[split reverse],
				nil
			  ];
	[self runAction: [CCSequence actions:
			   [self easeActionWithAction:seq],
			   [CCCallFunc actionWithTarget:self selector:@selector(finish)],
			   [CCStopGrid action],
			   nil]
	 ];
}

-(CCActionInterval*) action
{
	return [CCSplitCols actionWithCols:3 duration:duration/2.0f];
}

-(CCActionInterval*) easeActionWithAction:(CCActionInterval*)action
{
	return [CCEaseInOut actionWithAction:action rate:3.0f];
}
@end

//
// SplitRows Transition
//
@implementation CCTransitionSplitRows
-(CCActionInterval*) action
{
	return [CCSplitRows actionWithRows:3 duration:duration/2.0f];
}
@end


#pragma mark Fade Grid Transitions

//
// FadeTR Transition
//
@implementation CCTransitionFadeTR
-(void) sceneOrder
{
	inSceneOnTop = NO;
}

-(void) onEnter
{
	[super onEnter];
	
	CGSize s = [[CCDirector sharedDirector] winSize];
	float aspect = s.width / s.height;
	int x = 12 * aspect;
	int y = 12;
	
	id action  = [self actionWithSize:ccg(x,y)];

	[outScene runAction: [CCSequence actions:
					[self easeActionWithAction:action],
				    [CCCallFunc actionWithTarget:self selector:@selector(finish)],
				    [CCStopGrid action],
				    nil]
	 ];
}

-(CCActionInterval*) actionWithSize: (ccGridSize) v
{
	return [CCFadeOutTRTiles actionWithSize:v duration:duration];
}

-(CCActionInterval*) easeActionWithAction:(CCActionInterval*)action
{
	return action;
//	return [EaseIn actionWithAction:action rate:2.0f];
}
@end

//
// FadeBL Transition
//
@implementation CCTransitionFadeBL
-(CCActionInterval*) actionWithSize: (ccGridSize) v
{
	return [CCFadeOutBLTiles actionWithSize:v duration:duration];
}
@end

//
// FadeUp Transition
//
@implementation CCTransitionFadeUp
-(CCActionInterval*) actionWithSize: (ccGridSize) v
{
	return [CCFadeOutUpTiles actionWithSize:v duration:duration];
}
@end

//
// FadeDown Transition
//
@implementation CCTransitionFadeDown
-(CCActionInterval*) actionWithSize: (ccGridSize) v
{
	return [CCFadeOutDownTiles actionWithSize:v duration:duration];
}
@end
