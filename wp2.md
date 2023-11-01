## Table of Contents

1. Introduction
2. Literature review
3. Boots as builds
4. Security

**Abstract.** We consider bootstrapping computers, also known as bare metal provisioning, in a more general context of deployments and dependent builds. We review the state of the art, exhibit a Make-inspired data model that expresses builds declaratively and specialize it to a boot context, and introduce a trust-oriented security model for provisioning.

## Introduction

Booting computers has long been a somewhat neglected corner of IT infrastructure. It is often easy to ignore the sequence of unfamiliar and usually poorly documented environments a computer quickly steps through between a power cycle and normal operation. Indeed, a correctly configured system should spend only a tiny fraction of its life cycling through these stages.

Despite this, there are a few reasons one may wish to expend attention on the bootloader. One is *security.* In order to evaluate the security of the software supply chain used in a computer system, one must trace the root of trust all the way to the beginning of the boot sequence.

A second, related issue is *reproducibility*, that is, the art of getting servers into the same state regardless of the starting environment. [Why do we have to go all the way back to bare metal for that?] This is related to the idea of *immutable infrastructure*, otherwise known as the [phoenix server](https://martinfowler.com/bliki/PhoenixServer.html) model. In a HA cluster with at least two physical nodes, this power cycle $\rightarrow$ bare metal redeployment can be achieved with zero downtime. See also "reproducible builds" (https://hal.science/hal-03196519/, https://reproducible-builds.org).

We think the bootloader is overdue a modern theoretical treatment. A well-defined data model for defining boot sequences can have a number of benefits:

* Accessibility. A clear, up-to-date description language means more users understanding and taking control of their own boot sequences.
* Security. #TODO
* Extensibility. The present obscure state of documentation makes it difficult for developers to integrate new technologies such as novel storage backends early in the boot process.

### Related work

UEFI is a set of cross-platform standards for an execution environment presented by platform firmware which early stage boot manager or bootloader software can hook into. The UEFI specification includes a systematic and quite general language for defining *locations* for sourcing images. (https://uefi.org/specs/UEFI/2.10/10_Protocols_Device_Path_Protocol.html) Insofar as the difficulty of designing a boot often reduces to the difficulty of telling the early boot environment how to locate images, the UEFI devpath language is quite useful for reproducible boots.

Some of this work is replicated by the ACPI and DeviceTree standards. UEFI DevPaths can invoke ACPI descriptors.

EBBR is a subset of UEFI designed as a specification compatible with U-Boot, the industry standard firmware and bootloader implementation for embedded systems. https://arm-software.github.io/ebbr/

The multiboot specification (and its sequel) does some work to define the format of bootloaders. Multiboot-compliant bootloaders can be executed by GRUB. This spec is defined at a finer grain than most of the examples discussed in this document. Also, it does not appear to be widely implemented.

The *boot loader specification* project (https://uapi-group.org/specifications/specs/boot_loader_specification/), much like the current work, has the stated goal of defining an interoperable boot specification format. However, the boots definable by this format are limited to ones where the boot artifacts are located on local storage, which must be partitioned in one of a few pre-defined layouts. Thus *extensibility* cannot be said to be one of the goals of the project.

In modern data centre operations, it is typical to use a network boot based bare metal deployment framework. Such frameworks may obscure the intricacies of setting up the PXE protocol and attempt to make provisioning a "machine cloud" feel similar to provisioning a cloud of application containers running on a container workload management system (e.g. Kubernetes). See Openstack Ironic, Tinkerbell, Canonical's MaaS, and so on. In some cases, these frameworks can be managed directly through the same tools that are used to manage other, more abstract layers of infrastructure (e.g. Hashicorp Terraform).

The OpenStack authors have also written on the pros and pitfalls of bare metal provisioning.
https://www.openstack.org/use-cases/bare-metal/how-ironic-delivers-abstraction-and-automation-using-open-source-infrastructure

## Boots as computations with cacheing

A boot can be regarded as a set of steps to compute the state of an initialized system. In some cases, recomputing the value with updated inputs (i.e. rebooting) can be accelerated using a caching strategy, so that a reboot may occur without necessarily going through a full power cycle (e.g. switch-root, `kexec`).

In this section, we repeatedly make use of an analogy with building (i.e. compiling) software artifacts.

### Data model


**Definition.** An *n-ary operation* from types $(T_1,\ldots,T_n)$ to type $T_0$ is defined to be a function $f:\prod_{i=1}^n T_i \rightarrow T_0$. Note that we index the output and inputs (in that order) of an $n$-ary operation by $[n]:=\{0,\ldots,n\}$.

A *task* is an operation $f$ (of any arity $n$) together with a labelling $\mathtt{name}:[n]\rightarrow \mathtt{String}$ of the inputs and output by strings and a "task description," which should be an expression of the underlying function understandable to the computer environment in which this computation will be executed. The label $\mathtt{name}(0)$ of the output of the operation is called the *target* of the task.

A *build specification* or simply *build* is a set of tasks. Expressed in a Python-like pseudocode, the data schema looks something like the following:

```python=
[
    (f, name_0, [name_1, ..., name_n]),
    ...
]
```
In this picture, the task description would be a Python function and the labelled source and destination types are denoted by (typed) named variables. (This is purely illustrative and is certainly not supposed to suggest a bootloader implemented in Python!)

Or a more precisely specced JSON
```json
[
    {
        "target": {"label": "name_0", "type": "T_0"},
        "inputs": [
            {"label": "name_1", "type": "T_1"},
            ...,
            {"label": "name_n", "type": "T_n"},
        ],
        "task": @td
    },
    ...
]
```
Here `@td` should be some task description schema whose details we leave completely open.

A build specification is said to be *solved* if each target is the output of at most one task. A solved build can be represented as a DAG.

Let $B$ be a build and $t$ a target of $B$, and $(i_1,\ldots,i_k)$ a set of labels. A *solution* of $(B,t,(i_1,\ldots,i_k))$ is a subset $S$ of $B$ such that:

* $t$ is a *root* of $S$, that is, it is the unique target that is not also an input.
* $i_1,\ldots,i_k$ are the leaves of $S$, i.e. they are the only inputs that are not also targets.
* Every target in $S$ is the output of at most one rule in $S$.

In other words, a solution of $(B,t,(i_1,\ldots,i_k))$ defines a way to compute an element of $T_t$ given elements of $T_{i_1},\ldots,T_{i_k}$.

*Example. (Makefiles as build specifications)*. We can express the same data in a Makefile-like syntax as follows:
```makefile=
name_0: name_1, ... name_n
    echo $(f name_1 ... name_n) > name_0
```
This can be understood as a genuine Makefile if:

* All the inputs and outputs are "files;" that is, $T_i=\mathtt{File}$ for all $i$. For the purposes of Make, a *file* can be understood as a tuple $(\mathtt{name},\mathtt{mtime}, \mathtt{data})$.
* `f` is a shell function.
* Each label appears as the output of at most one step.

Recipes in real-life Makefiles (and indeed any build system) are often not pure functions, but rather depend implicitly on some system state whose scope varies on a per-target basis. 
If one's goal is reproducibility, efforts should be made to make all boot dependencies *explicit.*

*Example. (Dependency DAGs).* It is quite common to encode collections of dependent computations as a directed acyclic graph (DAG). If a build has the property that each target appears as the output of at most one rule, then it can be exactly encoded as a DAG with one node for each target and input, where each non-leaf nodes is decorated by the unique rule of which it is a target.

### Multiple providers

Unlike DAGs, our data model is flexible enough to describe builds with multiple recipes (each as good as any other) for the same target. In the language of dependency management, our dependency formulae are allowed to contain logical disjunction as well as conjunction. 

Disjunctive dependencies are extremely common in practical deployment scenarios such as RPM or DEB-based package management, where objects or configuration rules listed as a dependency of a given package may have several provider packages, only one of which need be installed to satisfy the dependency.

Naturally, examples of multiple providers in the boot process are also plentiful.

* The feature `EFI_BOOT_SERVICES` is provided by any UEFI-compliant firmware (for example Tianocore EDK2), but also by any firmware complying with the more stripped-down EBBR specification, such as U-Boot.
* HTTP and other network drivers are available in UEFI, GRUB, or a Linux initramfs.
* Linux filesystems such as Ext4 and BTRFS each have providers in the form of GRUB and Linux modules, but are not available in UEFI.
* An IP address can be provided either by a static configuration option or via DHCP, either of which itself has several providers spread across different boot stages.

### Build stages

A boot system requires multiple computations that take place at different times and in different contexts. For example, a UEFI firmware boot into an EFI executable needs to compute the state of an initialized system starting from only a "reset vector." 

Meanwhile, the contents, installation location, and configuration of firmware can be computed ahead of time in the context of a fully equipped development OS. All that we need to know to compute this is the shape of the computation demanded by the boot environment. That is, are we starting from the reset vector? From an EBBR firmware? From GRUB?

By expressing the boot-time computation as a higher order function parametrized by the inputs to the build-time computation, we can express the full computation as a *single* build specification together with a labelling of the leaves that partitions them into "boot-time" and "build-time."


Tasks:
1. Build kernel.
2. Build initramfs containing desired *rootfs drivers*.
3. Install kernel + initramfs to location accepted by kernel invoker (GRUB).
4. Build GRUB menu (i.e. `grub.cfg`).
5. Build and install GRUB image.
6. Build initramfs with all drivers required for a given GRUB menu included.
7. Build initramfs with all default drivers included.

In the following examples, I use the Pythonic notation and explain the typing (for which there are often multiple reasonable approaches) in prose.

### Example: low-level

We start from the assumption that we want to load and boot into an EFI executable file `BOOTX64.EFI`.

1. To jump into this program (i.e. compute the state of an initialized system running this program), we need the program binary itself and a firmware library function to parse and load PE executable with EFI headers.
2. To obtain the library function `efi_exec`, we need to resolve the symbol from a loaded firmware implementation providing this feature. Libraries that implement either the UEFI or EBBR specifications provide it.
3. A UEFI symbol table can be computed by loading it from a UEFI implementation, such as Tianocore's OVMF firmware for virtual machines. It is presumed that this firmware is loaded from a canonical location (e.g. NVRAM) known to the first stage bootloader, so we do not add further tasks to source this.
4. The EFI program binary can be computed by fetching it from a storage location. We can treat the system I/O bus as an oracle from which we fetch things by passing an address. For example, within the UEFI abstraction layer, this address could be typed as a [UEFI Device Path](https://uefi.org/specs/UEFI/2.10/10_Protocols_Device_Path_Protocol.html). (Again, the fetcher will need to resolve symbols for the drivers to resolve these paths --- for example, a VFAT filesystem and mass storage device driver --- but to avoid repetition in this purely illustrative example, we do not make these tasks explicit in the listing below.)
5. The boot device path is read from the boot menu table in the EFIVARS section of NVRAM. The line number is either the configured default or is entered in an interactive user session.
6. `efi-boot-number` is a natural number, denoting the menu entry selected by a user via an interactive console session.

We could go still further and define providers of `Console` (e.g. UART serial or graphical output), but the point has been made.

```python=
[
    ("apply", "Exec(BOOTx64.EFI)", ["efi_exec", "BOOTX64.EFI"]),
    ("get_name", "efi_exec", ["Implements(UEFI)"]),
    ("get_name", "efi_exec", ["Implements(EBBR)"]),
    ("load", "Implements(UEFI)", ["OVMF.fd"]),
    ("fetch", "BOOTX64.EFI", ["boot-device-path"]),
    ("get_line", "boot-device-path", ["efi-bootmenu", "efi-boot-number"]),
    ("input", "efi-boot-number", ["Console", "efi-bootmenu", "USER"])
]
```

The leaves of this build specification are the values `Console`, `efi-bootmenu`, `USER`, and `OVMF.fd`. Of these, `USER` is boot-time and the rest are build time. If the firmware implementation is considered as a separate input to the EFI variables, then these could be further divided into *build-time* versus *configure-time*.

In practice, it could be used to select and automatically configure a firmware image that boots into an EFI executable selected from a list by a user, given the boot menu contents and a working console configuration. 

Note that in this application, some leaf variables (`efi-bootmenu` and console configuration) can be easily reconfigured without reinstalling the firmware image itself. This is called making use of a cached build output.

### Example: Linux with a kernel command line

Here's how a typical invocation of the kernel (such as one defines in GRUB) might break down.

1. To initialize the state, we need a Linux image (let us say a blob `vmlinuz` in bzImage format) and a kernel commandline. The kernel command line must at least have a `root=` argument. If an initramfs is used, we also need the underlying data for that as well as the corresponding command line argument; for simplicity, we do not discuss that case. Let us call the executor `bzImage_exec`; it is provided, for example, by GRUB.
2. The input `vmlinuz` has type $\mathbb{B}^\star$, while the other leaves `root` and `extra_params` have type $\mathtt{String}$.
3. A more careful specification of this boot could restrict the type of `root` to forms accepted by the kernel at boot without an initramfs, such as a Linux device path (`/dev/*`) or partition UUID. Similarly, `extra-params` could be further broken down by specifying optional fields for each parameter the kernel recognises. (Note that the Linux kernel doesn't mind being passed parameters it not recognize: it will simply silently ignore them.)
4. If the bootloader also has to fetch `vmlinuz` from a peripheral (i.e. it is not already assumed to reside in a hardcoded location), then we can add a fetch stage for that too. The type of the input `kernel-path` should depend on the environment and available drivers for fetching. For example, if the implicit context is GRUB, `kernel-path` should be typed as a [GRUB path](https://www.gnu.org/software/grub/manual/grub/grub.html#Naming-convention).

```python=
# Boot without initramfs, fetching vmlinuz
[
    ("bzImage_exec", "Exec(Linux)", ["vmlinuz", "cmdline"]),
    ("join", "cmdline", ["root", "extra-params"]),
    ("fetch", "vmlinuz", ["kernel-path"])
]
```

The leaves of the build are `kernel-path`, `root`, and `extra-params`. These leaves could all be marked as boot-time and reduced using input from an interactive user session (the GRUB shell or menu editor). 

Alternatively, they could themselves be expressed as targets of a GRUB menu selection, with the leaves of the larger build being `USER` (boot-time) and the data of a GRUB menu (configure-time). Reducing the configure-time parameters yields the GRUB script `${prefix}/grub.cfg` sourced by GRUB on start. This reduction is often computed with a distro-provided shell script like `grub-mkconfig`.

### Example: high-level

Multi-stage boot involving GRUB and an initramfs. You need to go to multi-stage because the resources you need to fetch need codecs/drivers not available at the initial boot stage.

Tasks:
1. Build kernel.
2. Build initramfs containing desired *rootfs drivers*.
3. Install kernel + initramfs to location accepted by kernel invoker (GRUB).
4. Build GRUB menu (i.e. `grub.cfg`).
5. Build and install GRUB image.
6. Build initramfs with all drivers required for a given GRUB menu included.
7. Build initramfs with all default drivers included.

Each task needs its own build specification. Question: is it possible to

Example:
1. You want to boot a kernel that lives on a filesystem other than FAT. For example, `ext4` or `btrfs`. Your target `btrfs` has a disjunctive dependency `grub || linux`. Similarly, the kernel is an ELF executable and not an EFI PE; this also has a disjunctive dependency `grub || linux`.
2. You want to boot a kernel that lives on an attached storage device whose filesystem may be any of a list of supported filesystems. Which one it is is autodetected on startup (a dynamic dependency).
3. You want to boot an image comprising more than one file; for instance, a kernel and initramfs. The dependency is `ipxe || grub || linux`.
4. You want to fetch an image from a novel tech (Swarm, IPFS, Arweave...) that has been developed for a full OS, e.g. Linux, BSD, MacOS, Windows. Your dependency is that OS and an init process that launches the client for the novel protocol.
5. You want to capture user input interactively. That is, your build has a dynamic dependency.
   - Selection from several hardcoded boot options. Available in UEFI.
   - Selection from several boot options with an interactive editor to modify them. Dependency is `grub`.
   - Shell with various capabilities. Available UEFI, GRUB, Linux+initramfs...
6. You want to fetch an image from the WAN over HTTP with static network configuration. You need network interface drivers, a TCP/IP stack, and HTTP.
7. Same as above but with HTTPS. In addition to the above you need TLS and root certificates (as trust anchor or with trust derivable from a trust anchor).
8. Same as 5. but also verifying a PGP signature. You need PGP and the signing pubkey (as trust anchor or with trust derivable from a trust anchor).
9. Same as 5. but also verifying a modern signature scheme with less widespread support, such as BLS with signature aggregation. Dependency is `bls-verify -> linux` (probably.)
10. Same as 5, 6, or 7, but with autoconf (a dynamic dependency). You need `ra || dhcp || dhcpv6.`
11. Same as 5, 6, or 7, but the image URL is a DNS name rather than an IP address. You need `dns-client`. (If using DHCP, you need a DHCP client plugin that registers the DNS server address field.)

### Example: fetchers

A common theme in the preceding family of examples is that the choke point is *fetching* an image or configuration from a distant location to a proximal one (e.g. main memory). In full generality, a fetcher has the following inputs:

* The address of the thing to be fetched.
* The driver (fetcher function) used to fetch the thing.
* The state of the external system hosting the thing.

How many of these parameters we include in a build specification depends on the intended scope of the analysis or configuration. For example, it would be natural to omit the last parameter if the object to be fetched is hosted on an external, curated repository. The second parameter can be omitted if the driver is already an implicit part of the context.


## Security

* If we use the "Confidentiality, Integrity, Availability" (CIA) model of security goals:
  * *Confidentiality* is often not the focus of the boot process. If a boot input contains confidential data, confidentially is generally the responsibility of the subsystem that stores that data; handled, for example, by encryption at rest.
  * *Integrity* is a major concern of boot processes and much of the boot security infrastructure that exists is designed to address this goal.
  * *Availability* refers to non-interruptibility of the boot process. Availability of boot inputs --- for example, a boot image fetched from a remote store --- is the responsibility of the fetching and remote storage subsystem.

Threat models such as STRIDE (Spoofing, Tampering, Repudiation, Information disclosure, DOS, Elevation of privilege) tell a similar story.

In this section we focus on *integrity,* the most widely appreciated security goal of a boot flow.

### Integrity/tampering boot security problem

In the boot as computation "graph" model described in this article, a generic security problem runs as follows:

*Context.* A user wants to compute a target $t$ of a build $B$ in several stages $S_1,\ldots,S_n$. At each stage, some inputs are consumed and some intermediate targets $t'$ are computed.

*Adversary.* Between each stage, the (tampering) adversary may modify the value of the intermediate targets $t'$.

*Security goal.* The result of the computation is either the true value of $t$ or $\bot$, indicating failure.




### Some examples

#### U-Boot standard boot

*Context.* An ARM SoC with (trusted) U-Boot firmware is booting a [FIT image](https://u-boot.readthedocs.io/en/latest/usage/fit/source_file_format.html) comprising a kernel, initramfs, device tree blob, and kernel commandline stored on an SD card.

*Adversary.* May modify the contents of the SD card after the user writes it but before booting.

*Security goal.* Either the specified FIT image is booted, or the boot fails and the system halts.

* Resource on this and related problem. https://www.timesys.com/security/securing-u-boot-a-guide-to-mitigating-common-attack-vectors/
* Tools for securing U-Boot configuration. https://research.nccgroup.com/2020/12/16/depthcharge-v0-2-0/

#### Traditional package management



*Context.* A user downloads and install a program from a remote repository.

*Adversary.* May modify data in transit and at rest on the remote repository.

*Security goal.* The installed package is the subject of a claim of authorship by an entity possessing an given public key $\mathtt{pk}$.

* In widely used package repositories, a package is accompanied by a checksum/hash and a signature of that checksum (in .asc = ASCII-armored PEM format). 
* The signature is accompanied by a field indicating the claim associated to the signature in a commonly understood format, for example, the OpenPGP Signature Type byte 0x00 ([RFC 4880](https://www.rfc-editor.org/rfc/rfc4880.html#section-5.2.1)).
* The trust of the signing key can be derived from that of the root certificate of a TLS certificate chain, for example, those of the DNS domain from which the key is fetched. This could be the domain hosting the repository itself or a domain known to be owned by the software author or other trusted authority.



## References

- A few papers about build systems.
- OSTree and related projects. "Bootable containers." 
- Kairos and SENA. 
- [Security related things]

### Articles

- Secure boot vulnerability. https://arstechnica.com/information-technology/2023/03/unkillable-uefi-malware-bypassing-secure-boot-enabled-by-unpatchable-windows-flaw/
- Phoenix server. https://martinfowler.com/bliki/PhoenixServer.html

### Docs

- Bootloader specification. https://uapi-group.org/specifications/specs/boot_loader_specification/
- Fedora COPR (build service). https://docs.pagure.org/copr.copr/index.html
- Open build service (SUSE). https://openbuildservice.org/help/manuals/obs-user-guide/
- OSTree. A "git-like" model for committing and downloading bootable filesystem trees. https://ostreedev.github.io/ostree/
  - bootc. Boot and upgrade via container images. https://github.com/containers/bootc
- Kairos. An OS distributed as a container. https://kairos.io
  - Whitepaper. https://github.com/kairos-io/kairos/files/11250843/Secure-Edge-Native-Architecture-white-paper-20240417.3.pdf

### Papers

- Mokhov, Mitchell, Jones. (2020). *Build systems à la carte: Theory and practice.*
  - https://ndmitchell.com/downloads/paper-build_systems_a_la_carte_theory_and_practice-21_apr_2020.pdf
- Spall, Mitchell, Tobin-Hochstadt. (2022). *Forward build systems, formally.* 
  - https://ndmitchell.com/downloads/paper-forward_build_systems_formally-17_jan_2022.pdf
- Nguyen, Nguyen, Phan. (2022). *Analyzing the CMake build system.* 
  - https://research.facebook.com/publications/analyzing-the-cmake-build-system/
- 

### Bare metal provisioning

Some or all of these may have Terraform "providers."

- Packet.org, acquired by Equinix. Uses kexec(). https://tinkerbell.org/
- OpenStack Ironic. https://wiki.openstack.org/wiki/Ironic
- Canonical. Windows or Ubuntu centric. https://maas.io
- Focus on workstations. https://fogproject.org
- https://www.theforeman.org
- Cobbler. Linux installation/update server. https://cobbler.github.io
- RackN Digital Rebar (paid) https://rackn.com/rebar/

Biased comparison. https://rackn.com/support/resources/compare/

### Image repositories

- OpenStack (disk image; has compatible bare metal deployment tool). https://docs.openstack.org/glance/latest/
- Vagrant (disk image). https://app.vagrantup.com/boxes/search
