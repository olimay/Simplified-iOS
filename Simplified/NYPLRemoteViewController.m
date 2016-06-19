#import "NYPLConfiguration.h"
#import "NYPLJSON.h"
#import "NYPLReloadView.h"
#import "NYPLRemoteViewController.h"
#import "UIView+NYPLViewAdditions.h"
#import "NYPLAlertController.h"
#import "NYPLProblemDocument.h"
#import "SimplyE-Swift.h"

@interface NYPLRemoteViewController () <NSURLConnectionDataDelegate>

@property (nonatomic) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic) NSURLConnection *connection;
@property (nonatomic) NSMutableData *data;
@property (nonatomic, strong)
  UIViewController *(^handler)(NYPLRemoteViewController *remoteViewController, NSData *data, NSURLResponse *response);
@property (nonatomic) NYPLReloadView *reloadView;
@property (nonatomic, strong) NSURLResponse *response;

@end

@implementation NYPLRemoteViewController

- (instancetype)initWithURL:(NSURL *const)URL
          completionHandler:(UIViewController *(^ const)
                             (NYPLRemoteViewController *remoteViewController,
                              NSData *data,
                              NSURLResponse *response))handler
{
  self = [super init];
  if(!self) return nil;
  
  if(!handler) {
    @throw NSInvalidArgumentException;
  }
  
  self.handler = handler;
  self.URL = URL;
  
  return self;
}

- (void)load
{
  if(self.childViewControllers.count > 0) {
    UIViewController *const childViewController = self.childViewControllers[0];
    [childViewController.view removeFromSuperview];
    [childViewController removeFromParentViewController];
    [childViewController didMoveToParentViewController:nil];
  }
  
  [self.connection cancel];
  
  NSURLRequest *const request = [NSURLRequest requestWithURL:self.URL
                                                 cachePolicy:NSURLRequestUseProtocolCachePolicy
                                             timeoutInterval:5.0];
  
  self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
  self.data = [NSMutableData data];
  
  [self.activityIndicatorView startAnimating];
  
  [self.connection start];
}

#pragma mark UIViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.view.backgroundColor = [NYPLConfiguration backgroundColor];
  
  self.activityIndicatorView = [[UIActivityIndicatorView alloc]
                                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
  [self.view addSubview:self.activityIndicatorView];
  
  // We always nil out the connection when not in use so this is reliable.
  if(self.connection) {
    [self.activityIndicatorView startAnimating];
  }
  
  __weak NYPLRemoteViewController *weakSelf = self;
  self.reloadView = [[NYPLReloadView alloc] init];
  self.reloadView.handler = ^{
    weakSelf.reloadView.hidden = YES;
    [weakSelf load];
  };
  self.reloadView.hidden = YES;
  [self.view addSubview:self.reloadView];
}

- (void)viewWillLayoutSubviews
{
  [self.activityIndicatorView centerInSuperview];
  [self.activityIndicatorView integralizeFrame];
  
  [self.reloadView centerInSuperview];
  [self.reloadView integralizeFrame];
}

#pragma mark NSURLConnectionDataDelegate

- (void)connection:(__attribute__((unused)) NSURLConnection *)connection
    didReceiveData:(NSData *const)data
{
  [self.data appendData:data];
}

- (void)connection:(__attribute__((unused)) NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
  self.response = response;
}

- (void)connectionDidFinishLoading:(__attribute__((unused)) NSURLConnection *)connection
{
  [self.activityIndicatorView stopAnimating];
  
  NSHTTPURLResponse *const response = (NSHTTPURLResponse *)self.response;
  NSData *const data = self.data;
  
  self.response = nil;
  self.connection = nil;
  self.data = nil;
  
  if (response.statusCode == 200) {
    UIViewController *const viewController = self.handler(self, data, response);
    if(viewController) {
      [self addChildViewController:viewController];
      viewController.view.frame = self.view.bounds;
      [self.view addSubview:viewController.view];
      if(viewController.navigationItem.rightBarButtonItems) {
        self.navigationItem.rightBarButtonItems = viewController.navigationItem.rightBarButtonItems;
      }
      if(viewController.navigationItem.leftBarButtonItems) {
        self.navigationItem.leftBarButtonItems = viewController.navigationItem.leftBarButtonItems;
      }
      if(viewController.navigationItem.title) {
        self.navigationItem.title = viewController.navigationItem.title;
      }
      [viewController didMoveToParentViewController:self];
    } else {
      self.reloadView.hidden = NO;
      [self presentUnknownServerError];
    }
  } else if([response.MIMEType isEqualToString:@"application/problem+json"]
            || [response.MIMEType isEqualToString:@"application/api-problem+json"]) {
    id const JSON = NYPLJSONObjectFromData(data);
    if([JSON isKindOfClass:[NSDictionary class]]) {
      ProblemDetail *const problemDetail = [[ProblemDetail alloc] initWithJSON:JSON];
      if(problemDetail) {
        [problemDetail presentAsAlertOnViewController:self completion:nil];
      } else {
        self.reloadView.hidden = NO;
        [self presentUnknownServerError];
      }
    } else {
      self.reloadView.hidden = NO;
      [self presentUnknownServerError];
    }
  } else {
    self.reloadView.hidden = NO;
    [self presentUnknownServerError];
  }
}

#pragma mark NSURLConnectionDelegate

- (void)connection:(__attribute__((unused)) NSURLConnection *)connection
  didFailWithError:(__attribute__((unused)) NSError *)error
{
  [self.activityIndicatorView stopAnimating];
  
  self.reloadView.hidden = NO;
  
  self.connection = nil;
  self.data = nil;
  self.response = nil;
  
  UIAlertController *const alertController =
    [UIAlertController
     alertControllerWithTitle:NSLocalizedString(@"ConnectionFailed", nil)
     message:[error localizedDescription] ? [error localizedDescription] : NSLocalizedString(@"CheckConnection", nil)
     preferredStyle:UIAlertControllerStyleAlert];
  
  [alertController addAction:[UIAlertAction
                              actionWithTitle:NSLocalizedString(@"OK", nil)
                              style:UIAlertActionStyleDefault
                              handler:nil]];
  
  [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark -

- (void)presentUnknownServerError
{
  UIAlertController *const alertController =
  [UIAlertController
   alertControllerWithTitle:NSLocalizedString(@"ConnectionFailed", nil)
   message:NSLocalizedString(@"RemoteViewControllerUnknownServerErrorMessage", nil)
   preferredStyle:UIAlertControllerStyleAlert];
  
  [alertController addAction:[UIAlertAction
                              actionWithTitle:NSLocalizedString(@"OK", nil)
                              style:UIAlertActionStyleDefault
                              handler:nil]];
  
  [self presentViewController:alertController animated:YES completion:nil];
}

@end
