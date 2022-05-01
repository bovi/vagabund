# susi - QEMU-based CLI VM manager for macOS

## Usage

### Install template

To download and install a default VM base machine use:

```susi --install```

This command will download Ubuntu 20.04 Server, create a base image
and start it. Afterwards it will instantiate a VNC session to perform
the installation. Currently you have to peform the installation by 
hand. The following things need to be considered during installation:

- create user ```susi``` with password ```susi```
- install OpenSSH Server

### Work with VM

First an environment needs to be initialized:

```susi --init vm1,vm2,vm3```

This command creates the environment file ```susi.json```. This file
contains the definition of each machine for this environment.

To start the guest type:

```susi up```

This command will create a linked clone of the default template and
start the machines defined in ```susi.json```.

To connect to the guest via SSH type:

```susi ssh```

To connect to the guest via VNC type:

```susi vnc```

After you are finished the guest can be shutdown by typing:

```susi down```

### Adding USB devices to the VM

```susi``` comes with an USB wizard which helps to add USB devices to the
machine. You can just type:

```susi usb```

And the wizard is being started. Follow the instruction to add USB device(s)
to the ```susi.json``` file. The defined USB device(s) will be added to the
guest.
