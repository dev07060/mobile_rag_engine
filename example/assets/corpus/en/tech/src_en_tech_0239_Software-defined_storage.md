# Software-defined storage

- source_key: src_en_tech_0239
- language: en
- domain: tech
- length_bucket: long
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Software-defined_storage

---

Software-defined storage (SDS) is a marketing term for computer data storage software for policy-based provisioning and management of data storage independent of the underlying hardware. Software-defined storage typically includes a form of storage virtualization to separate the storage hardware from the software that manages it. The software enabling a software-defined storage environment may also provide policy management for features such as data deduplication, replication, thin provisioning, snapshots, copy-on-write clones, tiering and backup.
Software-defined storage (SDS) hardware may or may not also have abstraction, pooling, or automation software of its own. When implemented as software only in conjunction with commodity servers with internal disks, it may suggest software such as a virtual or global file system or distributed block storage. If it is software layered over sophisticated large storage arrays, it suggests software such as storage virtualization or storage resource management, categories of products that address separate and different problems. If the policy and management functions also include a form of artificial intelligence to automate protection and recovery, it can be considered as intelligent abstraction. Software-defined storage may be implemented via appliances over a traditional storage area network (SAN), or implemented as network-attached storage (NAS), or using object-based storage. In March 2014 the Storage Networking Industry Association (SNIA) began a report on software-defined storage.

Software-defined storage industry
VMware used the marketing term "software-defined data center" (SDDC) for a broader concept wherein all the virtual storage, server, networking and security resources required by an application can be defined by software and provisioned automatically.
Other smaller companies then adopted the term "software-defined storage", such as Cleversafe (acquired by IBM), and OpenIO.
Based on similar concepts as software-defined networking (SDN),
interest in SDS rose after VMware acquired Nicira for over a billion dollars in 2012.
Data storage vendors used various definitions for software-defined storage depending on their product-line. Storage Networking Industry Association (SNIA), a standards group, attempted a multi-vendor, negotiated definition with examples.
The software-defined storage industry is projected to reach $86 billion by 2023.
Building on the concept of VMware, esurfing cloud has launched a new software-defined storage product called HBlock. HBlock is a lightweight storage cluster controller that operates in user mode. It can be installed on any Linux operating system as a regular application without root access, and deployed alongside other applications on the server. HBlock integrates unused disk space across various servers to create high-performance and highly available virtual disks. These virtual disks can be mounted to local or other remote servers using the standard iSCSI protocol, revitalizing storage resources on-site without impacting existing operations or requiring additional hardware purchases.

Characteristics
Characteristics of software-defined storage may include the following features:

Abstraction of logical storage services and capabilities from the underlying physical storage systems, and in some cases pooling across multiple different implementations. Since data movement is relatively expensive and slow compared to computation and services, pooling approaches sometimes suggest leaving it in place and creating a mapping layer to it that spans arrays. Examples include:
Storage virtualization, the generalized category of approaches and historic products. External-controller based arrays include storage virtualization to manage usage and access across the drives within their own pools. Other products exist independently to manage across arrays and/or server DAS storage.
Virtual volumes (VVols), a proposal from VMware for a more transparent mapping between large volumes and the VM disk images within them, to allow better performance and data management optimizations. This does not reflect a new capability for virtual infrastructure administrators (who can already use, for example, NFS) but it does offer arrays using iSCSI or Fibre Channel a path to higher admin leverage for cross-array management apps written to the virtual infrastructure.
Parallel NFS (pNFS), a specific implementation which evolved within the NFS community but has expanded to many implementations.
OpenStack and its Swift, Ceph and Cinder APIs for storage interaction, which have been applied to open-source projects as well as to vendor products.
A number of Object Storage platforms are also examples of software-defined storage implementations.
Number of distributed storage solutions for clustered file system or distributed block storage are good examples of software defined storage.
Automation with policy-driven storage provisioning with service-level agreements replacing technology details. This requires management interfaces that span traditional storage-array products, as a particular definition of separating "control plane" from "data plane", in the spirit of OpenFlow. Prior industry standardization efforts included the Storage Management Initiative – Specification (SMI-S) which began in 2000.
Commodity hardware with storage logic abstracted into a software layer. This is also described as a clustered file system for converged storage.

Storage hypervisor
In computing, a storage hypervisor is a software program which can run on a physical server hardware platform, on a virtual machine, inside a hypervisor OS or in the storage network. It may co-reside with virtual machine supervisors or have exclusive control of its platform. Similar to virtual server hypervisors a storage hypervisor may run on a specific hardware platform, a specific hardware architecture, or be hardware independent.
The storage hypervisor software virtualizes the individual storage resources it controls and creates one or more flexible pools of storage capacity. In this way it separates the direct link between physical and logical resources in parallel to virtual server hypervisors. By moving storage management into isolated layer it also helps to increase system uptime and High Availability. "Similarly, a storage hypervisor can be used to manage virtualized storage resources to increase utilization rates of disk while maintaining high reliability."
The storage hypervisor, a centrally-managed supervisory software program, provides a comprehensive set of storage control and monitoring functions that operate as a transparent virtual layer across consolidated disk pools to improve their availability, speed and utilization.
Storage hypervisors enhance the combined value of multiple disk storage systems, including dissimilar and incompatible models, by supplementing their individual capabilities with extended provisioning, data protection, replication and performance acceleration services.
In contrast to embedded software or disk controller firmware confined to a packaged storage system or appliance, the storage hypervisor and its functionality spans different models and brands and types of storage [including SSD (solid state disks), SAN (storage area network) and DAS (direct attached storage) and Unified Storage(SAN and NAS)] covering a wide range of price and performance characteristics or tiers. The underlying devices need not be explicitly integrated with each other nor bundled together.
A storage hypervisor enables hardware interchangeability. The storage hardware underlying a storage hypervisor matters only in a generic way with regard to performance and capacity. While underlying "features" may be passed through the hypervisor, the benefits of a storage hypervisor underline its ability to present uniform virtual devices and services from dissimilar and incompatible hardware, thus making these devices interchangeable. Continuous replacement and substitution of the underlying physical storage may take place, without altering or interrupting the virtual storage environment that is presented.
The storage hypervisor manages, virtualizes and controls all storage resources, allocating and providing the needed attributes (performance, availability) and services (automated provisioning, snapshots, replication), either directly or over a storage network, as required to serve the needs of each individual environment.
The term "hypervisor" within "storage hypervisor" is so named because it goes beyond a supervisor, it is conceptually a level higher than a supervisor and therefore acts as the next higher level of management and intelligence that sits above and spans its control over device-level storage controllers, disk arrays, and virtualization middleware.
A storage hypervisor has also been defined as a higher level of storage virtualization software, providing a "Consolidation and cost: Storage pooling increases utilization and decreases costs. Business availability: Data mobility of virtual volumes can improve availability. Application support: Tiered storage optimization aligns storage costs with required application service levels". The term has also been used in reference to use cases including its reference to its role with storage virtualization in disaster recovery and, in a more limited way, defined as a volume migration capability across SANs.

Server vs. storage hypervisor
An analogy can be drawn between the concept of a server hypervisor and the concept of a storage hypervisor. By virtualizing servers, server hypervisors (VMware ESX, Microsoft Hyper-V, Citrix Hypervisor, Linux KVM, Xen, z/VM) increased the utilization rates for server resources, and provided management flexibility by de-coupling servers from hardware. This led to cost savings in server infrastructure since fewer physical servers were needed to handle the same workload, and provided flexibility in administrative operations like backup, failover and disaster recovery.
A storage hypervisor does for storage resources what the server hypervisor did for server resources. A storage hypervisor changes how the server hypervisor handles storage I/O to get more performance out of existing storage resources, and increases efficiency in storage capacity consumption, storage provisioning and snapshot/clone technology. A storage hypervisor, like a server hypervisor, increases performance and management flexibility for improved resource utilization.

See also
Hypervisor
Software-defined networking
Software-defined data center

References
