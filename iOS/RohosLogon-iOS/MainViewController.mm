//
//  MainViewController.m
//
//
//  Created by Alexandr Silonosov on 02-1-2014.
//  Copyright (c) 2014 Tesline-Service SRL. All rights reserved.
//  Rohos Logon Key client for iOS
//  rohos.com
//

#import "MainViewController.h"
#import <QRCodeReader.h>
#import <Decoder.h>
#import <TwoDDecoderResult.h>
#import <CommonCrypto/CommonCryptor.h>

#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <arpa/inet.h>




/*
 Authentication Record structure with encryption routine
 */
class AuthRecord
{
public:
    NSString *userName; // user account name or rohos disk name
    NSString *hostName; // host name (computer name)
    NSString *secretKey; // secret key (AES 128 encryption key, generated by PC)
    NSString *data;      // secret data with authentication info (encrypted user name, pwd, encryption keys)
    NSString *hostIP;    // PC ip for future
    int hostPort;       // host PORT  (may differs for each record)
    
    NSString *authSignalString;
    NSString *serverReplyStr;
    
    AuthRecord()
    {
        userName = @"";
       // hostName = @"";
    }
    
    bool isEmpty() {
        if (userName == nil || [userName length] ==0)
            return true;
        return false;
        
    };
    
    NSData *AES128Encrypt(NSData* data) {
        // 'key' should be 32 bytes for AES256, will be null-padded otherwise
        char keyPtr[kCCKeySizeAES256+4]; // room for terminator (unused)
        bzero(keyPtr, sizeof(keyPtr)); // fill with zeroes (for padding)
        if ([secretKey length] > 64)
            return nil;
        
        NSData *key = dataByIntepretingHexString(secretKey);
        memcpy(keyPtr, [key bytes], [key length]);
        // fetch key data
        //[key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
        
        NSUInteger dataLength = [data length]+2;
       
        //See the doc: For block ciphers, the output size will always be less than or
        //equal to the input size plus the size of one block.
        //That's why we need to add the size of one block here
        size_t bufferSize = dataLength + kCCBlockSizeAES128;
        void *buffer = malloc(bufferSize);
        
        size_t numBytesEncrypted = 0;
        CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt, kCCAlgorithmAES, /*kCCOptionPKCS7Padding |*/ kCCOptionECBMode,
                                              keyPtr, kCCKeySizeAES128,
                                              NULL /* initialization vector (optional) */,
                                              [data bytes], dataLength, /* input */
                                              buffer, bufferSize, /* output */
                                              &numBytesEncrypted);
        if (cryptStatus == kCCSuccess) {
            //the returned NSData takes ownership of the buffer and will free it on deallocation
            return [NSData dataWithBytesNoCopy:buffer length:numBytesEncrypted];
        }
        
        free(buffer); //free the buffer;
        return nil;
    }
    

    // HexToData
    NSData *dataByIntepretingHexString(NSString *hexString) {
        char const *chars = hexString.UTF8String;
        NSUInteger charCount = strlen(chars);
        if (charCount % 2 != 0) {
            return nil;
        }
        NSUInteger byteCount = charCount / 2;
        uint8_t *bytes = (uint8_t*)malloc(byteCount);
        for (int i = 0; i < byteCount; ++i) {
            unsigned int value;
            sscanf(chars + i * 2, "%2x", &value);
            bytes[i] = value;
        }
        return [NSData dataWithBytesNoCopy:bytes length:byteCount freeWhenDone:YES];
    }
    
    // DataToHex
    NSString *hexadecimalString(NSData* data) {
        /* Returns hexadecimal string of NSData. Empty string if data is empty.   */
        
        const unsigned char *dataBuffer = (const unsigned char *)[data bytes];
        
        if (!dataBuffer)
            return [NSString string];
        
        NSUInteger          dataLength  = [data length];
        NSMutableString     *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];
        
        for (int i = 0; i < dataLength; ++i)
            [hexString appendString:[NSString stringWithFormat:@"%02lx", (unsigned long)dataBuffer[i]]];
        
        return [NSString stringWithString:hexString];
    }

    // creates unique Authentication Signal based on TimeStamp, Random and authentication data
    NSString *getEncryptedDataString()
    {
        //// XXXXXXXX TTTTTTTT '0001' '0002'
        ////
               uint32_t intSeconds = (uint32_t)([[NSDate date] timeIntervalSince1970]);
        uint32_t intRand = arc4random();
        uint8_t shortP = 0;
        uint8_t shortP1 = '0';
        uint8_t shortP2 = '1';
        
        // lets convert for Android compatibility
        uint32_t secondsAsABigEndianNumber = CFSwapInt32HostToBig(intSeconds);
       
        
        NSData* dataBytes = dataByIntepretingHexString(data);
        uint8_t dataLen = [dataBytes length];
        
              NSMutableData *payload = [[NSMutableData alloc] init];
        [payload appendBytes:&intRand length: sizeof(uint32_t)];
        [payload appendBytes:&secondsAsABigEndianNumber length: sizeof(uint32_t)];
        [payload appendBytes:&shortP length: sizeof(uint8_t)]; // put zero
        [payload appendBytes:&shortP1 length: sizeof(uint8_t)]; // put value . 0030
        [payload appendBytes:&shortP length: sizeof(uint8_t)];
        [payload appendBytes:&shortP2 length: sizeof(uint8_t)];
        [payload appendBytes:&shortP length: sizeof(uint8_t)];
        [payload appendBytes:&dataLen length: sizeof(uint8_t)];
        [payload appendBytes: [dataBytes bytes] length: dataLen];
        
        Byte buff1[200];
        memcpy(buff1, [payload bytes], [payload length]);
        
        
        //NSData *rawData = [NSData dataWithBytes: [payload bytes] length: [payload length] ];
        NSData *cipher = AES128Encrypt(payload);
        if (cipher!=nil)
        {
            // Formatting Authentication signal : HOSTNAME.USERNAME.HEXDATA
            NSString* enc_str = hexadecimalString(cipher);
            authSignalString = [NSString stringWithFormat:@"%@.%@.%@", userName, hostName, enc_str];
            return authSignalString;
        }
        
        return @""; //oops!
        
    }
    
    
};

AuthRecord ar;

#define AUTHREC_LIST_KEY @"listOfAuthRecords"

#define USER_NAME_KEY @"userName"
#define HOST_NAME_KEY @"hostName"
#define SECRET_NAME_KEY @"secret"
#define DATA_NAME_KEY @"data"
#define PORT_NAME_KEY @"port"
#define IP_NAME_KEY @"ip"


@interface MainViewController ()

@end

@implementation MainViewController
{
  BluetoothCentral* mBluetooth;
  NSData* mBluetoothSendData;
}

@synthesize resultsView;
@synthesize tableView;
@synthesize recordsView;
@synthesize bigLogoView;

@synthesize resultsToDisplay;
@synthesize qrReader;


- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    self.qrReader = [[NSMutableSet alloc] init];
    QRCodeReader *qrcodeReader = [[QRCodeReader alloc] init];
    [self.qrReader addObject:qrcodeReader];
    
    // adding Single Tap recognozer to Label and BigLogo images to open "rohos.com... "
    
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(learnMoreSingleTapRecognized:)];
    singleTap.numberOfTapsRequired = 1;
    [resultsView addGestureRecognizer:singleTap];
    [singleTap release];
    
    singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(learnMoreSingleTapRecognized:)];
    singleTap.numberOfTapsRequired = 1;
    [bigLogoView addGestureRecognizer:singleTap];
    [singleTap release];
    
    
    // the mutalbe array of all debts
     NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    mRecords = [[defaults objectForKey:AUTHREC_LIST_KEY] mutableCopy];
    
    if (mRecords == nil)
    {
        mRecords = [[NSMutableArray alloc] init];
    }

    if ([mRecords count] == 0)
    {
        recordsView.hidden = YES;
        
    } else
    {
    
        [self refreshAuthRecordsList];
    }
  
    mBluetooth = [[BluetoothCentral alloc] init];
    mBluetooth.delegate = self;
}

- (void)dealloc {
  [mBluetoothSendData release]; mBluetoothSendData = nil;
  [mBluetooth release]; mBluetooth = nil;
  [super dealloc];
}

- (void)learnMoreSingleTapRecognized:(UIGestureRecognizer *)gestureRecognizer {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://rohos.com/mob"]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (int)saveAuthRecord:( AuthRecord *) r
{
    // pointer to standart user defaults
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    
    // the mutalbe array of all debts
    // mRecords = [[defaults objectForKey:AUTHREC_LIST_KEY] mutableCopy];
    // create new record
    
    NSDictionary * newRecord = nil;
    
    if (mRecords != nil && [mRecords count] >0)
    {
        for (NSDictionary* rec in mRecords) {
            NSString *uName = [rec objectForKey:USER_NAME_KEY];
            NSString *hostName = [rec objectForKey:HOST_NAME_KEY];
            if ( [uName isEqualToString:r->userName ] &&
                [hostName isEqualToString:r->hostName ] )
            {
                // the same record...
                // todo - update secrt key and data...
                return 0;
            }
        }
    }

    
    if (newRecord == nil)
    {
    // to save CGFloat you need to wrap it into NSNumber
    NSNumber * port = [NSNumber numberWithInt:r->hostPort];
    
    newRecord = [NSDictionary
            dictionaryWithObjects:[NSArray arrayWithObjects: r->userName, r->hostName, r->secretKey, r->data, port, r->hostIP, nil]
            forKeys:[NSArray arrayWithObjects:USER_NAME_KEY, HOST_NAME_KEY, SECRET_NAME_KEY, DATA_NAME_KEY, PORT_NAME_KEY, IP_NAME_KEY, nil]];
        
        if (mRecords == nil)
            mRecords = [[NSMutableArray alloc] init];
    
    }
    
    
    [mRecords addObject:newRecord];
    [defaults setObject:mRecords forKey:AUTHREC_LIST_KEY];
    
    // do not forget to save changes
    [defaults synchronize];
    
    return 0;
}


- (int)refreshAuthRecordsList
{
    bigLogoView.hidden = YES;
    recordsView.hidden = NO;
    
   // [self.tableView beginUpdates];
    //[self.tableView endUpdates];

    [self.tableView reloadData];

    return 0;
}

- (int)sendBroadcastPacket:( AuthRecord *) r
{
    // Open a socket
    int sd = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sd <= 0) {
        NSLog(@"Error: Could not open socket");
        return -1;
    }
    
    // Set socket options
    // Enable broadcast
    int optionVal = 1;
    int ret = setsockopt(sd, SOL_SOCKET, SO_BROADCAST, &optionVal, sizeof(optionVal));
    if (ret) {
        NSLog(@"Error: Could not open set socket to broadcast mode");
        close(sd);
        return ret;
    }
    
    struct timeval tv;
    tv.tv_sec = 3;  /* 3 Secs Timeout */
    tv.tv_usec =0;
    //optionVal = 10;
    ret=setsockopt(sd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(timeval));
    
    if (ret == -1)
    {
        optionVal = 10;
        ret=setsockopt(sd, SOL_SOCKET, SO_RCVTIMEO, &optionVal, sizeof(int));
        
    }
    
    // Since we don't call bind() here, the system decides on the port for us, which is what we want.
    
    // Configure the port and ip we want to send to
    struct sockaddr_in broadcastAddr; // Make an endpoint
    memset(&broadcastAddr, 0, sizeof broadcastAddr);
    broadcastAddr.sin_family = AF_INET;
    inet_pton(AF_INET, "255.255.255.255", &broadcastAddr.sin_addr); // Set the broadcast IP address
    broadcastAddr.sin_port = htons(r->hostPort); // Set port 1900
    
    // Send the broadcast request, ie "Any upnp devices out there?"
    const char *request = [r->authSignalString cStringUsingEncoding:NSUTF8StringEncoding];
    ret = sendto(sd, request, strlen(request), 0, (struct sockaddr*)&broadcastAddr, sizeof broadcastAddr);
    if (ret<0) {
        NSLog(@"Error: Could not open send broadcast");
        close(sd);
        return ret;
    }
    
    // Get responses here using recvfrom if you want...
    /*char replyBuff[290]={0};
    struct sockaddr_in remoteAddr; // Make an endpoint
    
    socklen_t addrLen = sizeof(remoteAddr);
    ret = recvfrom(sd, replyBuff, 250, 0, (struct sockaddr *) &remoteAddr, &addrLen );
   
    
    if (ret>0)
    {
        r->serverReplyStr = [NSString stringWithUTF8String:replyBuff];
    }*/
    
    r->serverReplyStr = @"Authentication signal has been sent!";
    
     close(sd);
    return ret;
}

//
// send Authentication Signal of default record
// called when app is just reopened
//
- (void)sendSignalForRecord: (int) recordIndex
{
    if (mRecords == nil || [mRecords count] < recordIndex+1 )
    {
        return;
    }
    
    NSDictionary * record =[mRecords objectAtIndex:recordIndex];
    
    AuthRecord r;
    
    r.hostName = record[HOST_NAME_KEY];
    r.hostPort = [record[PORT_NAME_KEY] intValue];
    r.secretKey = record[SECRET_NAME_KEY];
    r.data = record[DATA_NAME_KEY];
    r.userName = record[USER_NAME_KEY];
    
    [self sendSignalUpdateUI: &r];
    
    return;

}

//
// send Authentication Signal by using the record ar
//
//
- (int)sendSignalUpdateUI:( AuthRecord *) ar
{
    if (ar->isEmpty())
        return 0;
    
    NSLog(@"host: %@", ar->hostName);
    
    NSString *strEncrypted = ar->getEncryptedDataString();
    
    NSLog(@"%@", strEncrypted);
    
    
    //lets send multicast over WiFi...
    
    if ([self sendBroadcastPacket:ar] >0 )
    {
        [resultsView setText:ar->serverReplyStr];
    } else
    {
        [resultsView setText:@"Signal sent but not unlocked"];
    }
  
    if (mBluetooth.isActive)
        [mBluetooth sendData: [ar->serverReplyStr dataUsingEncoding: NSUTF8StringEncoding]];
    else
    {
      [mBluetoothSendData release];
      mBluetoothSendData = [[ar->serverReplyStr dataUsingEncoding: NSUTF8StringEncoding] retain];
      [mBluetooth start];
      // Logic continues in onCentralManagerInit handler
    }
    return 0;
}

// delete lis button..
- (IBAction)sendSignalPressed:(id)sender
{
    [mRecords removeAllObjects];
 
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    
    [defaults setObject:mRecords forKey:AUTHREC_LIST_KEY];
    
    // do not forget to save changes
    [defaults synchronize];
    
    [self refreshAuthRecordsList];
    
    recordsView.hidden = YES;
    bigLogoView.hidden = NO;
    
    [resultsView setText:@"Install Rohos Logon Key on your desktop to enable authentication by phone. rohos.com/mob"]; //NSLocalizedString(@"Intro", @"How to start")];
    
    
}

- (IBAction)scanPressed:(id)sender
{
    /*
     // enable to allow quick QR-code recognition
    
    [self parseUriString:@"rohos1://192.168.2.106:1205/insp?USER=Jane(KEY=0be5a4cc7508b9e9edd99cedd04a7e6d15b87faf(DATA=74bf9bfe531a52da3615255185aa2e9268bca0fda5498908e49e02ccbc63aee30de1a9cbc3d0ac739b715a1a4cfb63b4db1832384718c5e3ae3abbe77b6daf18"];
     
    return;
    */
    
    ZXingWidgetController *widController = [[ZXingWidgetController alloc] initWithDelegate:(id)self showCancel:YES OneDMode:NO];
    NSMutableSet *readers = [[NSMutableSet alloc] init];
    QRCodeReader * qrcodeReader = [[QRCodeReader alloc] init];
    [readers addObject:qrcodeReader];
    [qrcodeReader release];
    widController.readers = readers;
    [readers release];
    widController.soundToPlay = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"beep-beep" ofType:@"aiff"] isDirectory:NO];
    [self presentViewController:widController animated:YES completion:^{
        
    }];
    [widController release];
    
    /*
     // testing by image...
    UIImage *image = [UIImage imageNamed:@"qrcode.png"];
    Decoder *decoder = [[Decoder alloc] init];
    decoder.readers = self.qrReader;
    decoder.delegate = (id)self;
    [decoder decodeImage:image];
     */
}

/*
 parse Rohos Logon Key generated URL with authentication data
 
 URL example: rohos1://192.168.2.106:1205/insp?USER=Jane(KEY=0be5a4cc7508b9e9edd99cedd04a7e6d15b87faf(DATA=74bf9bfe531a52da3615255185aa2e9268bca0fda5498908e49e02ccbc63aee30de1a9cbc3d0ac739b715a1a4cfb63b4db1832384718c5e3ae3abbe77b6daf18
 
*/
- (void)parseUriString:(NSString*)strUri
{
    // replace all '(' with '&' - thats a trick for android.
    strUri = [strUri stringByReplacingOccurrencesOfString:@"(" withString:@"&"];
  
    // replace all ' ' with %20 - because [NSURL URLWithString] does not accept spaces
    strUri = [strUri stringByReplacingOccurrencesOfString: @" " withString: @"%20"];
    NSURL *url = [NSURL URLWithString:strUri];
    
    ar.userName = @""; //
    
    
    NSLog(@"scheme: %@", [url scheme]);
    NSLog(@"host: %@", [url host]);
    NSLog(@"port: %@", [url port]);
    NSLog(@"path: %@", [url path]);
    NSLog(@"path components: %@", [url pathComponents]);
    NSLog(@"parameterString: %@", [url parameterString]);
    NSLog(@"query: %@", [url query]);
    NSLog(@"fragment: %@", [url fragment]);
    
    if ( ![[url scheme] isEqualToString:@"rohos1"])
    {
        return;
    }
    
    ar.hostPort = [[url port] intValue];
    ar.hostName = [[NSString stringWithString:[[url path] substringFromIndex:1]] retain];
    ar.hostIP = [[NSString stringWithString:[url host]] retain];
    
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    for (NSString *param in [[url query] componentsSeparatedByString:@"&"])
    {
        NSArray *elts = [param componentsSeparatedByString: @"="];
        if ([elts count] < 2)
          continue;
      
      NSString* value = [elts[1] stringByReplacingOccurrencesOfString: @"%20" withString: @" "];
      [params setObject: value  forKey: elts[0]];
    }
    
    ar.userName = [params objectForKey:@"USER"];
    ar.secretKey = [params objectForKey:@"KEY"];
    ar.data = [params objectForKey:@"DATA"];
    
    [resultsView setText:[NSString stringWithFormat:@"Auth data : %@", ar.hostName ]];
    
    [self saveAuthRecord:&ar];
    [self refreshAuthRecordsList];
    [self sendSignalUpdateUI:&ar];
    
    
    return;
    
    
}

// ZXing returns here
//
- (void)zxingController:(ZXingWidgetController *)controller didScanResult:(NSString *)result
{
    self.resultsToDisplay = result;
    if (self.isViewLoaded) {
        [resultsView setText:resultsToDisplay];
        [resultsView setNeedsDisplay];
        [self parseUriString:result];
    }
    [self dismissViewControllerAnimated:NO completion:^{
        
    }];
}


- (void)zxingControllerDidCancel:(ZXingWidgetController *)controller
{
    [self dismissViewControllerAnimated:YES completion:^{
        
    }];
}

- (void)decoder:(Decoder *)decoder willDecodeImage:(UIImage *)image usingSubset:(UIImage *)subset
{
    
}
- (void)decoder:(Decoder *)decoder didDecodeImage:(UIImage *)image usingSubset:(UIImage *)subset withResult:(TwoDDecoderResult *)result
{
   /* NSLog(@"result = %@", [result text]);
    [resultsView setText:[result text]];
    [resultsView setNeedsDisplay];*/
}

- (void)decoder:(Decoder *)decoder failedToDecodeImage:(UIImage *)image usingSubset:(UIImage *)subset reason:(NSString *)reason
{
    NSLog(@"%@", @"Failed to decode image!");
    [resultsView setText:[NSString stringWithFormat:@"Failed to decode QR-Code: %@", reason]];
    
}

- (void)decoder:(Decoder *)decoder foundPossibleResultPoint:(CGPoint)point
{
    
}


/*
 TableView interface
 
 */
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [mRecords count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *simpleTableIdentifier = @"SimpleTableItem";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:simpleTableIdentifier];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:simpleTableIdentifier];
    }
    NSDictionary * record = [mRecords objectAtIndex:indexPath.row];
    
    cell.textLabel.text = [NSString stringWithFormat:@"%@ [%@]",
                           [record objectForKey:USER_NAME_KEY],
                            [record objectForKey:HOST_NAME_KEY]
                           ];
    cell.imageView.image = [UIImage imageNamed:@"unlockpc.png"];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
   // UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    
    [self sendSignalForRecord: indexPath.row];
}

- (void)onCentralManagerInit:(NSError *)error
{
  if (error)
    NSLog(@"BT init & discovery error: %@", [error localizedDescription]);
  else
  if (mBluetoothSendData)
    [mBluetooth sendData: mBluetoothSendData];
}

- (void)onDataSent:(NSError *)error
{
  // Silence all errors for now. But dump to console.
  if (error)
    NSLog(@"BT send error: %@", [error localizedDescription]);
}

@end

