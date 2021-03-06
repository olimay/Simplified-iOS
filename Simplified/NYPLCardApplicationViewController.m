//
//  NYPLCardApplicationViewController.m
//  Simplified
//
//  Created by Sam Tarakajian on 10/6/15.
//  Copyright © 2015 NYPL Labs. All rights reserved.
//

#import "NYPLCardApplicationViewController.h"
#import "NYPLCardApplicationModel.h"
#import "NYPLSettings.h"
#import "NYPLRegistrationStoryboard.h"

@implementation NYPLCardApplicationViewController

- (id) initWithCoder:(NSCoder *)aDecoder
{
  self = [super initWithCoder:aDecoder];
  if (self) {
    self.navigationItem.title = self.title;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(dismiss)];
  }
  return self;
}

- (void) viewDidLoad
{
  [super viewDidLoad];
  if (!self.currentApplication)
    self.currentApplication = [NYPLCardApplicationModel currentCardApplication];
}

- (void) viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  if (self.viewDidAppearCallback) {
    self.viewDidAppearCallback();
  }
}

- (void)dismiss
{
  NYPLRegistrationStoryboard *storyboard = (NYPLRegistrationStoryboard *) self.storyboard;
  [self dismissViewControllerAnimated:YES completion: ^() {
    [storyboard.delegate storyboard:storyboard willDismissWithNewAuthorization:NO];
  }];
}

- (void) performSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
  [[NYPLSettings sharedSettings] setCurrentCardApplication:self.currentApplication];
  [super performSegueWithIdentifier:identifier sender:sender];
}

@end
