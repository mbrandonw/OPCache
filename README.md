#OPCache

Some additions to `NSCache` that make it a lot more useful. 

##URL Image Fetching

`OPCache` has a family of methods to facilitate loading external images, processing them (i.e. resizing, cropping, etc.), and stuffing them into a memory and/or disk cache. Processing of the images is done via an optional block that is run on a background queue.

`OPCache` tries to accomplish all of this in the most lightweight, efficient manner. For example, if you try loading the same URL multiple times, it will properly consolidate them into a single request. Also, an original copy of the image is stashed away on the disk so that subsequent calls to load the same image with different processing blocks will skip loading the image externally, and instead use the disk copy.

##Installation

We love [CocoaPods](http://github.com/cocoapods/cocoapods), so we recommend you use it.

##Demo

Checkout [OPKitDemo](http://www.opetopic.com) for a demo application using OPExtensionKit, among other things.

##Author

Brandon Williams  
brandon@opetopic.com  
[www.opetopic.com](http://www.opetopic.com)
