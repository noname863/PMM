## What is PMM
PMM stands for package manager manager. It is program to manage your
package manager, so you could manage your management of packages.

On the serious note, it is tool which helps reprodusing your system,
by managing a "recipy" for your system.

Idea is to store list of packages, your configuration files in
kinda the same format as dotfiles, and use it all to reproduce
"most" of the system if you have to. With this tool you can deploy
root and home configuration same way as dotfiles deploy, and
for list of packages there is command which makes sure that
only packages on the lists installed explicitly, and everything
else is (potentially indirect) dependency.

This is the tool which will help you document and store configuration.
If you want, you can even install software by storing binaries as
configuration.

### Packages
/etc/pmm/packages - required to be directory. It's children have to be directories
with names corresponding to the name of the package manager. For now only dnf and pacman
are supported. I intentionally didn't support pip, because it is often intertwined with
system package manager.

I may support in the future apt, and if I would need it I will
consider supporting snap, flatpac, and pipx. I will see whether npm or cargo ever have
packages which conflicts with system package manager.

Inside each folder for package manager, you can put text files with .packages extentions
each should contain list of packages, each package on the next line, without versions.
For now, pmm does not support specifying specific versions for packages, mostly because
on system package manager it will not be supported well: each update risks updating
package with specific version, and each install risks to be conflicting with old version.
We may support versions for pipx, and if flatpac and snap support them, there it would
also make sence.

.packages files can have comments starting with # and empty lines

### Configuration

To understand this section you need to know what GNU stow is, I would recommend
[this link](https://linux.die.net/man/8/stow).
Read description, and explanation in "Installing Packages" go get what tool does

Naming rest of the stuff that pmm does as "configuration" is a bit misleading, since
you can also deploy software the same way, and I would recommend deploy pmm itself
this way (unless this project somehow becomes so large, that I will start releasing
packages for distributions, in that case, use package manager). Basically, you have
two directories: /etc/pmm/config, and ~/$XDG_CONFIG_HOME/pmm/, which are root and home
configuration respectively (if $XDG_CONFIG_HOME is not found, .config is used)

Both root and home configuration directories should contain child directories,
which considered to be "packages". Then, for each package, we are going to
do operation same thing as GNU stow does (I don't want to explain here what stow is,
`man stow` may help you. I will describe stows we do). So for example when we do
--apply-home, it is equivalent to doing `stow -d ~/$XDG_CONFIG_DIR/pmm -t ~/ --stow $PACKAGE_NAME`
to each package in ~/$XDG_CONFIG_DIR/pmm. --cleanup-home is going to do
`stow -d ~/$XDG_CONFIG_DIR/pmm -t ~/ --delete $PACKAGE_NAME`. Root operations are going to use root (/ directory)
as and -d parameter to stow, and going to take packages from /etc/pmm/config.
You can also specify package name after --apply and --cleanup operation, to do it for specific package, instead
of all of them.

Notably, we do not depend on stow, instead it is essentially reimplemented here.

While above I was a bit of sidetracked explaining what operations do instead of explaining
configuration format, I did it to say that contents of the packages is the same,
as when you use stow for configuration management.

And again, you can store other stuff than configuration. One of the ways I would initially use
pmm, is I would put pmm binary into /etc/pmm/config/pmm/usr/bin directory, and used
```
sudo /etc/pmm/config/pmm/usr/bin/pmm --apply-root
```
This would make pmm deploy itself into /usr/bin, and would make it accessable globally.
You can use similar trick to deploy any software that you built from source:
just use /etc/pmm/config/$package_name/usr as install prefix when building from source,
and then after corresponding --apply-root every build artifact is going to be
deployed to /usr.


## Commands
* --apply-home:   Applies home configuration
* --cleanup-home:    Removes symlynks from home configuration
* --force-apply-home:   Applies home configuration, removes files which are on the way
* --preview-apply-home:   Prints which symlinks are going to be created, and which files are going to be overwritten by --apply-home/--force-apply-home
* --preview-cleanup-home:   Prings which symlinks are going to be deleted, and which symlinks are missing on --cleanup-home
* --apply-root:   Applies root configuration
* --cleanup-root:  Removes symlynks from root configuration
* --force-apply-root:   Removes symlynks from home configuration
* --preview-apply-root:   Prints which symlinks are going to be created, and which files are going to be overwritten by --apply-root/--force-apply-root
* --preview-cleanup-root:   Prings which symlinks are going to be deleted, and which symlinks are missing on --cleanup-root
* --apply-packages:  Reads all packages which should be installed on the system from config, then makes sure that they are installed, their dependencies (recursively), and nothing else. Most likely will require sudo
* --preview-packages:   Shows which packages will be installed and removed if you use apply packages
* --help:  Prints this list of commands, with this explanation

### TODO
We should create .config/$XDG_CONFIG_HOME if directory is not found
Support apt
Support cargo
Support pipx
Support specific versions (only for pipx, potentially for flatpak and snap)
Support flatpak
Support snap
Consider supporting npm (though it may conflict with system package manager, the same way pip does)

### Stuff that will never be supported
pip package manager support will never be added.

Mostly because it is often clashes with system package manager: We cannot
determine which packages are excessive, because we don't know which packages
are installed by user, and which packages are installed by system package manager.

My general opinion is that if you use it for project, use venv, and if you want
install software from pip, use pipx instead.


