#import "NYPLSession.h"
#import "NYPLBook.h"
#import "NYPLBookAcquisition.h"
#import "NYPLBookDownloadFailedCell.h"
#import "NYPLBookDownloadingCell.h"
#import "NYPLBookNormalCell.h"
#import "NYPLMyBooksDownloadCenter.h"
#import "NYPLReaderViewController.h"
#import "NYPLRootTabBarController.h"
#import "NSURLRequest+NYPLURLRequestAdditions.h"

#import "NYPLBookCellDelegate.h"

@implementation NYPLBookCellDelegate

+ (instancetype)sharedDelegate
{
  static dispatch_once_t predicate;
  static NYPLBookCellDelegate *sharedDelegate = nil;
  
  dispatch_once(&predicate, ^{
    sharedDelegate = [[self alloc] init];
    if(!sharedDelegate) {
      NYPLLOG(@"Failed to create shared delegate.");
    }
  });
  
  return sharedDelegate;
}

#pragma mark NYPLBookNormalCellDelegate

- (void)didSelectReturnForBook:(NYPLBook *)book
{
  [[NYPLMyBooksDownloadCenter sharedDownloadCenter] returnBookWithIdentifier:book.identifier];
}

- (void)didSelectDownloadForBook:(NYPLBook *)book
{
  [[NYPLMyBooksDownloadCenter sharedDownloadCenter] startDownloadForBook:book];
}

- (void)didSelectReadForBook:(NYPLBook *)book
{
  [[NYPLRootTabBarController sharedController]
   pushViewController:[[NYPLReaderViewController alloc]
                       initWithBookIdentifier:book.identifier]
   animated:YES];
}

- (void)didSelectReportForBook:(NYPLBook *)book sender:(UIButton *)sender
{
  NYPLProblemReportViewController *problemVC = [[NYPLProblemReportViewController alloc] initWithNibName:@"NYPLProblemReportViewController" bundle:nil];
  BOOL isIPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
  problemVC.modalPresentationStyle = isIPad ? UIModalPresentationPopover : UIModalPresentationOverCurrentContext;
  problemVC.popoverPresentationController.sourceView = sender;
  problemVC.popoverPresentationController.sourceRect = ((UIView *)sender).bounds;
  problemVC.book = book;
  problemVC.delegate = self;
  [[NYPLRootTabBarController sharedController] safelyPresentViewController:problemVC animated:YES completion:nil];
}

#pragma mark NYPLBookDownloadFailedDelegate

- (void)didSelectCancelForBookDownloadFailedCell:(NYPLBookDownloadFailedCell *const)cell
{
  [[NYPLMyBooksDownloadCenter sharedDownloadCenter]
   cancelDownloadForBookIdentifier:cell.book.identifier];
}

- (void)didSelectTryAgainForBookDownloadFailedCell:(NYPLBookDownloadFailedCell *const)cell
{
  [[NYPLMyBooksDownloadCenter sharedDownloadCenter] startDownloadForBook:cell.book];
}

#pragma mark NYPLBookDownloadingCellDelegate

- (void)didSelectCancelForBookDownloadingCell:(NYPLBookDownloadingCell *const)cell
{
  [[NYPLMyBooksDownloadCenter sharedDownloadCenter]
   cancelDownloadForBookIdentifier:cell.book.identifier];
}

#pragma mark NYPLProblemReportViewControllerDelegate

- (void)problemReportViewController:(NYPLProblemReportViewController *)problemReportViewController didSelectProblemWithType:(NSString *)type
{
  NSURL *reportURL = problemReportViewController.book.acquisition.report;
  if (reportURL) {
    NSURLRequest *r = [NSURLRequest postRequestWithProblemDocument:@{@"type":type} url:reportURL];
    [[NYPLSession sharedSession] uploadWithRequest:r completionHandler:nil];
  }
  [problemReportViewController dismissViewControllerAnimated:YES completion:^{
    [[NSNotificationCenter defaultCenter] postNotificationName:NYPLBookProblemReportedNotification object:problemReportViewController.book];
  }];
}

@end
