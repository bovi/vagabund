# susi

## USB Stuff

```lsusb``` alternative on macOS is ```system_profiler SPUSBDataType``` and
```ioreg -p IOUSB -w0 -l```.

For USB passthrough ```sudo``` is required. The following command needs the 
correct vendor and product id:

```
-device nec-usb-xhci -device usb-host,vendorid=0x????,productid=0x????
```

## References

https://gist.github.com/gsf/c7bb24178700ffcaeab9c100c63264bb
