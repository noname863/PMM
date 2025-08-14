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
  DLL hell is not solved.
2. There is no isolation if you decide to build a package in the environment
  created by PMM.
3. You can use regular package manager without changing pmm system configuration,
  if you want to install something into the system fast.

