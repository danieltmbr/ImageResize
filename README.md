Just a tiny wrapper around some C code to resize images.

I use this in my [web projects](https://github.com/danieltmbr/tmbr) where resizing was firt implemented by using CoreGraphics. However the server is hosted on Linux where CG is not avaialble. SwiftGD package would have been an ohter option but that relies on libraris installed to the system. Other C libraries supposedly are heavyweight. So this is the middle ground for now withoutadding 20k of C headers in my swift project source directly.

Don't expect any more features here.
