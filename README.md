## What is PMM
PMM stands for package manager manager. It is program to manage your
package manager, so you could manage your management of packages.

On the serious note, it is tool which helps reprodusing your system,
by managing a "recipy" for your system.

Idea is to store list of packages, your configuration files,
and list of files/paths which are "your business", and should
not be managed by this tool. Then, if you want, you can ask
this tool about how this system in the recipe differs from the
current system, and, if you want, update the system according
to the recipe.

It may sound something like what NixOS does, and it kinda is,
but it doesnt't use nix as underlying package manager. As a result
1. You can still fall to all of skill issues of using regular package
  manager, like having conflicting packages, and solving conflicts in the wrong ways.
  DLL hell and similar problems are not solved.
2. There is no isolation, if you decide to build a package in the environment
  created by PMM.
3. You can use regular package manager without changing pmm system configuration,
  if you want to install something into the system fast.

## Commands
*  --preview-apply: checks how system is different from the recipe.
*  --preview-apply-packages: checks which packages are not installed, and which packages are excessive
*  --preview-apply-config: check what will be added if config would be applied
*  --preview-apply-home: check what will happen if home config would be applied
*  --apply: applies recipe
*  --apply-packages: applies packages recipe
*  --apply-config: applies configuration
*  --apply-home: applies only home configuration. Can be run without sudo
*  --install: adds package(s) to the list of unsorted packages. Installs package(s) to the system
*  --uninstall: remove package(s) from all of the package lists. Uninstalls package(s) from the system

## Recipe format
Recipe is more of the metaphor, then a real format,
pmm configuration is spread through the system. There are two main
folders:
- /etc/pmm for system configuration
- $XDG_CONFIG_HOME/pmm (.config/pmm if $XDG_CONFIG_HOME does not exist) for home configuration

in /etc/pmm there is a system configuration. System configuration
consists of packages folder and config folder.

Packages is a folder which contains multiple text files, describing list of packages
(manually specifying dependencies is not nessesary) which should
be installed in the system.

Config folder is a folder which contains all overrides to the default configuration.
You should treat it as folder, which would be stowed
(check gnu utility [stow](https://www.gnu.org/software/stow/)) to the root of the system

Also, there is option to manage home configuration. Usually home would be marked as
"do not touch directory", to be in full control of the user. However a lot of
programs have both global and per user configuration, and it would be wierd to manage
global parts with pmm, and per user part with something else

$XDG_CONFIG_HOME/pmm contains just something which can be stowed to the home folder

