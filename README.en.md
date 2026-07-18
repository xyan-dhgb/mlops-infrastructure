# DESIGN AND IMPLEMENTATION OF AN MLOPS ARCHITECTURE FOR A MULTIMODAL DEEP LEARNING SYSTEM TO SUPPORT SKIN CANCER DIAGNOSIS

- English title: Design and implementation of an MLOps architecture for a multimodal deep learning system to support skin cancer diagnosis
- Instructor: MSc. Nguyen Khanh Thuat (thuatnk@uit.edu.vn)
- Members:
    - Dinh Huynh Gia Bao (22520101@gm.uit.edu.vn)
    - Tran Gia Bao (22520117@gm.uit.edu.vn)

## TABLE OF CONTENTS

- [Abstract](#abstract)
- [Directory Structure](#directory-structure)
- [Skin Cancer Situation](#skin-cancer-situation)
- [Theoretical Basis](#theoretical-basis)
    - [Overview of Skin Cancer](#overview-of-skin-cancer)
    - [SLICE-3D Dataset](#slice-3d-dataset)
- [Overview of Multimodal Deep Learning Model](#overview-of-multimodal-deep-learning-model)
- [Building MLOps Infrastructure](#building-mlops-infrastructure)
    - [Infrastructure as Code Development and Management](#infrastructure-as-code-development-and-management)
    - [Building EKS Infrastructure](#building-eks-infrastructure)
    - [Integrating Platform Applications on the EKS Cluster](#integrating-platform-applications-on-the-eks-cluster)
        - [Building Helm Bootstrap Mechanism via AWS Systems Manager](#building-helm-bootstrap-mechanism-via-aws-systems-manager)
        - [Deploying MLOps Platform Components](#deploying-mlops-platform-components)
    - [Accessing Internal Interfaces of Applications on the EKS Cluster](#accessing-internal-interfaces-of-applications-on-the-eks-cluster)
    - [Enabling GitOps Orchestration on the EKS Cluster](#enabling-gitops-orchestration-on-the-eks-cluster)
        - [App-of-Apps Model and AppProject](#app-of-apps-model-and-appproject)
        - [Automated Bootstrap Process using GitHub Actions](#automated-bootstrap-process-using-github-actions)
    - [Continuous Integration for Multimodal Deep Learning Source Code](#continuous-integration-for-multimodal-deep-learning-source-code)
    - [Deploying Training Pipeline on Argo Workflows](#deploying-training-pipeline-on-argo-workflows)
    - [Managing and Tracking Training Experiments](#managing-and-tracking-training-experiments)
    - [Building Model Inference Service with KServe Custom Predictor](#building-model-inference-service-with-kserve-custom-predictor)
    - [Building Continuous Integration and Continuous Deployment Pipeline for Inference Service](#building-continuous-integration-and-continuous-deployment-pipeline-for-inference-service)
    - [Developing Monitoring and Data Visualization System](#developing-monitoring-and-data-visualization-system)
- [Limitations](#limitations)
- [Drawbacks](#drawbacks)
- [Future Directions](#future-directions)
- [References](#references)

## ABSTRACT

**Skin cancer** is one of the most common skin diseases in the world, defined by the abnormal and uncontrollable growth of skin cells, primarily due to exposure to ultraviolet radiation. Although many cases can be treated effectively if detected at an early stage, accurately identifying and classifying skin lesions remains a challenge in medicine due to the specificities of evaluating multiple clinical data sources simultaneously and the reliance on doctors' professional experience.

In recent years, the development of **multimodal deep learning models** has shown potential in supporting doctors in analyzing diverse data sources to improve diagnostic accuracy. However, most current research focuses on improving model performance without paying adequate attention to the challenges of deploying, operating, and monitoring models in real-world environments.

After researching the issue, the student group proceeded to build a **Machine Learning Operations - MLOps system** for a multimodal deep learning model to support skin cancer detection, allowing automation of the entire model lifecycle from data management, training, deployment to post-deployment monitoring. At the same time, the group combined **two data sources: dermatological images and clinical data** to improve prediction efficiency.

This topic uses the **SLICE-3D** dataset from the **ISIC** organization from the Kaggle platform, including types of skin lesion images and clinical features. After handling data imbalance, the student group proceeded to build a multimodal deep learning model combining information from dermatological images and clinical data. The image branch uses **EfficientNetB3** to extract image features, while the tabular data branch is built on an **MLP** network. Features from both branches are fused together before being fed into a classifier to predict whether the skin lesion belongs to the **Malignant** or **Benign** group.

Experimental results show that the multimodal model achieves higher efficiency in balancing cancer detection capabilities and false alarm rates compared to many unimodal models. In addition, in terms of infrastructure, the built MLOps architecture automates the model development and deployment process, improving the system's reproducibility, manageability, and scalability.

## DIRECTORY STRUCTURE

```text
.
├── .github/          # GitHub Actions workflows for infrastructure and model CI/CD pipelines
├── asset/            # Image assets used in the documentation
├── docs/             # System design documents, diagrams, guides, and plans
├── environments/     # Terraform configurations (variables, backend) for environments (e.g., dev)
├── gitops/           # Kubernetes manifests managed by ArgoCD (App-of-Apps, Helm values)
├── modules/          # Reusable Terraform modules for AWS infrastructure (VPC, EKS, MLflow, Argo, KServe...)
├── src/              # Machine learning model source code (Serving, XAI, etc.)
└── web/              # Frontend web interface source code (React/Vite) for predictions
```

## SKIN CANCER SITUATION

Skin cancer is a disease in which skin cells grow abnormally and out of control. Most skin cancer cases are caused by overexposure to ultraviolet (UV) rays from the sun, tanning beds, or sunlamps [[1](https://www.cdc.gov/skin-cancer/about/index.html)]. Although many cases can be treated effectively when detected early, the disease still poses a risk because early signs are often very difficult to recognize. Medically, skin cancer is divided into two main groups: Melanoma and Non-melanoma skin cancer [[2](https://www.wcrf.org/preventing-cancer/cancer-types/skin-cancer/)].

According to data from the International Agency for Research on Cancer (IARC) under the World Health Organization (WHO) analyzed in-depth, skin cancer is creating a massive medical and financial burden globally. As of the end of 2022, non-melanoma skin cancer is one of the most common forms of cancer in the world with a burden exceeding **1.2 million** new cases recorded each year [[3](https://gco.iarc.who.int/media/globocan/factsheets/cancers/17-non-melanoma-skin-cancer-fact-sheet.pdf)]. Large-scale epidemiological studies indicate that the trend of case distribution is deeply differentiated by race and geographical region [[4](https://acsjournals.onlinelibrary.wiley.com/doi/10.3322/caac.21834)]. White populations living in areas with high UV radiation intensity such as **Australia, North America, and Europe** have the highest risk of skin damage.

In Vietnam, thanks to the characteristics of yellow skin with high natural melanin content that helps scatter harmful radiation, the incidence of skin cancer is significantly lower than in Western countries [[5](https://tamanhhospital.vn/co-the-nguoi/melanin/)]. However, there is a worrying fact that despite the low incidence rate, the mortality rate and severe complications from skin cancer in Vietnamese people are relatively high. The core difference lies in the clinical manifestation characteristics: while white people often get skin tumors in exposed areas exposed directly to the sun, melanoma in Vietnamese and Asian people in general mainly starts in the extremities (such as palms, soles, nail beds) [[6](https://dalieu.vn/ung-thu-da-hac-to-nhan-biet-som-nhu-the-nao-5537.html)]. Due to appearing in hidden locations, easily confused with benign moles or calluses, most patients in Vietnam only seek examination when the disease has progressed to a late stage. Actual statistics at the Ho Chi Minh City Hospital of Dermato-Venereology show that this unit receives nearly 3,000 patient visits for skin cancer examination and treatment each year, of which the group aged 60 and over accounts for an overwhelming proportion of over 90% [[6](https://dalieu.vn/ung-thu-da-hac-to-nhan-biet-som-nhu-the-nao-5537.html)].

## THEORETICAL BASIS

### Overview of Skin Cancer

Clinically and pathologically, skin cancer is divided into two major groups based on cell origin: non-melanoma skin cancer (NMSC) and melanoma. These two groups differ significantly in danger level, progression speed, and treatment prognosis [[7](https://www.nature.com/articles/s41598-025-90485-3)].

- **Non-melanoma skin cancer (NMSC)** is the most common group, primarily including two types:
    - **Basal Cell Carcinoma (BCC)**: This is the most common type of skin cancer, often developing in people with fair skin. People with dark skin can also develop this type of skin cancer [[8](https://www.aad.org/public/diseases/skin-cancer/types/common)]. About 75% out of 100 cases of non-melanoma skin cancer are BCC. They develop from basal cells, and these cells are found in the deepest part of the outermost layer of the skin (epidermis). Mainly developing on sun-exposed areas of the skin such as the head and neck, but can still develop on other parts of the body [[9](https://www.cancerresearchuk.org/about-cancer/skin-cancer/types)].

    - **Squamous Cell Carcinoma (SCC)**: It is the second most common type of skin cancer. People with light skin have a higher risk of developing SCC, and it can also develop in people with dark skin [[8](https://www.aad.org/public/diseases/skin-cancer/types/common)]. SCC usually grows faster than BCC. About 25% out of 100 cases of skin cancer are SCC. They start from cells called keratinocytes, located in the epidermis and develop on sun-exposed skin areas. These areas include parts of the head, neck, back of hands, and forearms [[9](https://www.cancerresearchuk.org/about-cancer/skin-cancer/types)].

- **Melanoma** is the most dangerous group, although it has a lower incidence rate but possesses rapid metastasis ability and high mortality rate if not detected early. Melanoma occurs when something transforms healthy melanocytes into cancer cells. Melanocytes are skin cells that produce the pigment that gives skin its color. This pigment is called melanin [[10](https://www.mayoclinic.org/diseases-conditions/melanoma/symptoms-causes/syc-20374884)].

### SLICE-3D Dataset

The dataset used by the student group in this thesis is **SLICE-3D**, published by the **ISIC** organization in **2024** in the Scientific Data journal belonging to Nature Publishing Group. This is also the official dataset of the **ISIC 2024 Grand Challenge** on the **Kaggle** platform.

This dataset was collected over **10 years**, from 2015 to 2024, from 9 hospitals and universities in the US, Australia, Spain, Austria, Greece, and Switzerland. This ensures diversity in ethnicity, imaging conditions, and medical equipment. In total, the dataset includes **401,059 skin lesion images** cropped from 3D total body photography, with a size of approximately **128x128** pixels in **JPEG** format [[11](https://www.kaggle.com/competitions/isic-2024-challenge/overview)].

Each image has accompanying clinical information in a separate consolidated file. This information includes **55 features**, such as age, sex, anatomical site of the lesion, and **over 30 TBP metrics**. These metrics are automatically extracted from 3D total body photography, including size, color contrast, and surface characteristics. The combination of these lesion images and clinical information forms the basis for the multimodal approach proposed in the thesis.

![SLICE-3D Dataset](/asset/image/isic-pics.png)

The **3D Total Body Photography (3D-TBP)** technology uses the **Vectra WB360** device system (from Canfield Scientific), applying an algorithm to reconstruct a 3D full-body skin surface mesh map, then automatically detects and extracts lesions into individual tiles of size _15mm×15mm_.

## OVERVIEW OF MULTIMODAL DEEP LEARNING MODEL

> [!NOTE]
> To realize the two components above into a complete system, the thesis proposes a general architecture presented in the following figure:

![Project Overview Model](/asset/image/thesis-project-overview-final.png)

The multimodal deep learning model for the **binary skin lesion classification problem** (Benign/Malignant) on the SLICE-3D dataset is built through the following steps:

- Data collection, data preprocessing, data splitting, and imbalance handling,
- Feature extraction for 2 separate data types:
    - Image feature processing branch: using the EfficientNetB3 model.
    - Clinical feature processing branch: using the MLP model.
- Multimodal model training, evaluation, XAI integration, and post-deployment monitoring.

The architecture is designed to simultaneously exploit both skin lesion image information and patient clinical data, thereby improving diagnostic capabilities compared to methods using only a single data source.

![Architecture of the multimodal deep learning model](/asset/image/multimodal-architecture.png)

The process begins with downloading data from Kaggle. The data then goes through a preprocessing phase, in which images are enhanced in quality using techniques such as CLAHE and Gaussian Blur, while tabular data is cleaned, encoded, and normalized.

Next, the dataset is split at a ratio of **64%/16%/20%** for the training, validation, and test sets using the **stratified split** method to maintain the class distribution ratio. Due to the high level of data imbalance between the two classes Benign and Malignant, the thesis applies a data imbalance handling mechanism before training to improve the ability to recognize malignant samples.

The model is built according to a multimodal architecture comprising two parallel processing branches. The image branch uses EfficientNetB3, the clinical data branch uses an MLP network. Features from the two branches are combined through a Fusion Head layer to form a unified multimodal representation serving the classification process.

The training process is carried out in two phases. In the first phase, the backbone of EfficientNetB3 is frozen and the model is trained with the Focal Loss function combined with oversampling techniques to focus on hard-to-learn samples. In the second phase, the backbone layers are unfrozen to perform fine-tuning, helping the model adapt better to the dermatological data domain while maintaining the features learned from ImageNet.

After completing the training, the model is evaluated using metrics such as **pAUC, AUC, Recall, and F1-score**. The optimal classification threshold is determined through a **threshold tuning** process to balance the ability to detect malignant cases and the false alarm rate. To enhance the transparency of the system, the thesis integrates **XAI** techniques to explain the basis of the model's predictions.

In addition, a **data drift** monitoring mechanism is built to track changes in data distribution before and after the training process.

## BUILDING MLOPS INFRASTRUCTURE

> [!NOTE]
> The Ops system is built on a Cloud-native platform, automating from source code integration, training to model monitoring and distribution.

### Infrastructure as Code Development and Management

_Code reference: [environments/dev](/environments/dev), [modules/](/modules)_

![Infrastructure Management Plan](/asset/image/git-workflow.png)

The figure above describes the Infrastructure as Code (IaC) deployment plan using **Terraform** combined with **GitHub Actions**. The process is built to automate the steps of checking, evaluating, and deploying infrastructure on the **AWS** platform, helping minimize manual errors, ensure consistency, and improve change management capabilities throughout the development lifecycle.

The process begins when a developer syncs source code from the **DEV** branch and creates a feature branch to make changes. After completion, the source code is pushed to **GitHub** and a **Pull Request** is created into the **DEV** branch. This action triggers a **workflow** on **GitHub Actions** to perform infrastructure source code checks (the **Build and Test Infrastructure as Code** phase in the [infrastructure CI workflow file](/.github/workflows/terraform-ci.yml)) before allowing the changes to be merged.

- **Checkov:** Performs static analysis on Terraform source code to detect security vulnerabilities and inappropriate configurations.
- **Terraform Validate:** Checks the validity of syntax, structure, and references in the Terraform source code.
- **Terraform Plan:** Analyzes the current infrastructure state and new Terraform source code to create a detailed deployment plan.
- **Upload Plan to Amazon S3:** The Terraform plan file is stored on Amazon S3 to ensure that the plan checked and approved during the Pull Request process will be the one used in the deployment phase.

When the Pull Request is approved and merged into the DEV branch, the student group can manually trigger the deployment pipeline. In the **Provision AWS Infrastructure** phase in the [infrastructure apply file](.github/workflows/terraform-apply.yml), the system will:

- **Verify:** The student group performs a final confirmation step before deployment to ensure that the changes have been checked and approved.
- **Download Plan from Amazon S3:** The system downloads the Terraform Plan file created and stored in the previous checking phase.
- **Terraform Apply:** Executes the downloaded Terraform Plan file. Terraform will interact with AWS services via API to create, update, or delete necessary resources, bringing the actual infrastructure state to the exact state described in the Terraform source code.

During development, testing, or when an environment is no longer needed, cleaning up resources to optimize costs is mandatory. The student group designed a separate pipeline ([infrastructure destroy file](.github/workflows/terraform-destroy.yml)) to safely destroy the infrastructure:

- **Verify:** Requires explicit confirmation from the developer before executing the infrastructure destruction process.
- **Terraform Plan Destroy:** Creates an infrastructure destruction plan, detailing all resources to be deleted.
- **Terraform Destroy:** Executes the process of deleting AWS resources managed by Terraform based on information in the Terraform State file.

### Building EKS Infrastructure

_Code reference: [modules/eks](/modules/eks), [modules/vpc](/modules/vpc)_

This is the architecture for deploying a **Kubernetes** cluster on **AWS** following a **Multi-AZ** model to ensure high availability, fault tolerance, and service continuity.

![EKS Cluster Architecture](/asset/image/eks-infrastructure-final.png)

Regarding network partitioning, the entire infrastructure is deployed within a **VPC** with the network address range **10.0.0.0/16**. The **VPC** is distributed across two **Availability Zones**, **ap-southeast-1a** and **ap-southeast-1b**, to ensure high availability and minimize impact when one zone encounters issues. Subnets are divided into 2 types to limit direct access from the **Internet** to critical components of the system.

A **NAT Gateway** is deployed in each public subnet to provide **Internet** access for resources located in private subnets. Through the **NAT Gateway**, **Worker Nodes** can perform tasks or access necessary **AWS** services without needing public **IP** addresses.

In addition, the system uses a **Bastion Host** as a centralized administrative access point. The student group can connect to the **Bastion Host** via **SSH** protocol, then perform administrative operations on resources located in private subnets. Connections are controlled by **Security Groups** to limit access according to the principle of least privilege established by the group.

After completing the network configuration, the student group proceeds to deploy the **Kubernetes** cluster through the AWS **EKS** service. The **EKS Control Plane** component orchestrates all activities of the **Kubernetes** cluster, including resource management, Pod scheduling, and maintaining the desired state of the system. To enhance security, the **EKS** cluster is configured with:

```terraform
endpoint_public_access = false
endpoint_private_access = true
```

This configuration ensures the **Kubernetes** API Server can only be accessed from within the **VPC** via the **Bastion Host**.

The system uses an **OIDC Provider** combined with the **IRSA (IAM Roles for Service Accounts)** mechanism to grant AWS access permissions to Kubernetes Pods. Through **IRSA**, each application or service in **Kubernetes** can be assigned a separate **IAM Role**. This allows **Pods** to access **AWS** services directly without using the permissions of the entire **Worker Node**.

The **Data Plane** part of **Kubernetes** is deployed via **EKS Managed Node Groups** and is distributed across both **Availability Zones** to increase fault tolerance and ensure service continuity. **Worker Nodes** are divided into three distinct functional groups:

- **Infra Node Group**: Runs foundational services such as **ArgoCD**, **Prometheus**, **Grafana**, **MLflow**, and **KServe Controller**.
- **GPU Node Group**: Dedicated to deep learning model training tasks requiring **NVIDIA GPU** resources.
- **CPU Node Group**: For data processing tasks that do not require **GPUs**.

Finally, the system uses separate **IAM Roles** for the **EKS Control Plane** and **Worker Nodes** to implement role-based access control according to function:

- **EKS Cluster Role**: Allows **EKS** to manage related **AWS** resources.
- **Worker Node Role**: Allows **Worker Nodes** to access and use necessary **AWS** resources.

### Integrating Platform Applications on the EKS Cluster

#### Building Helm Bootstrap Mechanism via AWS Systems Manager

_Code reference: [modules/bastion-host](/modules/bastion-host)_

![Helm Bootstrap Architecture using AWS Systems Manager](/asset/image/SSM-Bastion_host.png)

To ensure the initialization process of necessary applications on the **EKS** cluster is performed automatically, securely, and independently of direct **SSH** access, the student group implemented a Helm Bootstrap mechanism via **AWS Systems Manager**. This architecture allows the group to trigger a pipeline from **GitHub Actions**, then use **AWS Systems Manager** to establish secure connections to the **Bastion** servers within the **VPC**.

**Bastion Hosts** are deployed in **public subnets** across multiple **Availability Zones** to increase system availability. Through the **SSM Agent** installed on the **Bastion Host**, the pipeline can create **SSM Tunnel** sessions to execute **Kubernetes** administrative commands without opening the **SSH** port to the **Internet**. From the **Bastion Host**, **Helm** commands are used to interact with the **EKS** cluster located entirely in **private subnets**.

#### Deploying MLOps Platform Components

_Code reference: [gitops/apps](/gitops/apps)_

![Application Deployment Results](/asset/image/helm-bootstrap-result.png)

After successfully setting up the Helm Bootstrap mechanism, the group proceeds to deploy platform components serving the machine learning model development and operations lifecycle on the EKS cluster. All applications are packaged as Helm Charts and installed automatically via the built pipeline.

The system includes the following main components:

- **ArgoCD**: Manages application deployment following the GitOps model, synchronizing the Kubernetes cluster state with configurations stored in the Git repository.
- **Argo Workflows**: Orchestrates and executes data processing workflows, model training, and MLOps tasks as workflows.
- **MLflow**: Tracks experiments, manages training parameters, stores models, and manages the machine learning model lifecycle.
- **Prometheus**: Collects and stores monitoring metrics from Kubernetes and applications in the system.
- **Grafana**: Visualizes monitoring data, supporting the building of dashboards for operations.
- **cert-manager**: Automatically manages and renews TLS certificates for services in the cluster.
- **KServe**: Provides a platform for deploying and serving machine learning models on Kubernetes.
- **Cloudflare Tunnel**: Provides a secure access mechanism from the outside to internal services.

In addition, MLflow is configured to use two separate storage components:

- **Artifact Store**: Stores models and training files generated during experiments.
- **Backend Store**: Stores metadata of experiments and model management information.

### Accessing Internal Interfaces of Applications on the EKS Cluster

_Code reference: [modules/cloudflare](/modules/cloudflare), [gitops/apps/cloudflare.yaml](/gitops/apps/cloudflare.yaml)_

![Cloudflare Tunnel Configuration Deployed in EKS Cluster](/asset/image/cloudflare-eks.png)

In the system the student group is deploying, exposing internal administrative interfaces such as **ArgoCD, MLflow, Grafana, or Argo Workflows** to the Internet often brings many security risks. To solve the security problem and optimize operating costs, the group applied the **Cloudflare Tunnel** solution. This solution allows connecting internal services inside the EKS cluster to the Internet environment through a secure one-way encrypted tunnel from inside out (outbound connection). As a result, the EKS cluster does not need to open any inbound ports on the firewall or allocate public IPs, making the system completely immune to network scanning attacks.

The network flow is established as follows:

- **At Cloudflare Edge**: A **Tunnel** named **eks-tunnel** is initialized, acting as a transit gateway and DNS resolver.
- **At the EKS cluster**: A **Deployment** named **cloudflared-deployment** is deployed with high availability. These cloudflared **Pods** run in the background and maintain continuous connections to **Cloudflare Edge** via a **Tunnel token**.

Instead of using a complex internal **Ingress Controller**, routing is configured using a special **Cloudflare Ingress** file and applied via the **Helm Bootstrap pipeline**. When users access custom domains, **Cloudflare** routes the request through the network tunnel to the corresponding **ClusterIP** services inside **EKS** without going out to the public network.

However, not every application on the cluster is suitable to be exposed with a public domain name via **Cloudflare Tunnel**. For example, **Prometheus**, by default, has no authentication layer on its own web interface; anyone who obtains the URL can directly query all metrics, including sensitive infrastructure metrics (internal IP addresses, node names, resource configurations).

![Port-forward Method](/asset/image/port-forward.png)

The disadvantage of this method is its **manual nature**: the student group must keep two **SSH** sessions alive simultaneously throughout the access time, and only one person can use it at a time.

### Enabling GitOps Orchestration on the EKS Cluster

After completing the Helm bootstrap process through the [Integrating Platform Applications on the EKS Cluster](#integrating-platform-applications-on-the-eks-cluster) step, platform applications have been successfully deployed on the **Amazon EKS** cluster, and **Cloudflare Tunnel** provides external access capabilities to administrative interfaces. However, at this stage, **ArgoCD** is only installed and does not yet manage any applications according to the **GitOps** model. Therefore, the system needs to perform a bootstrap step to initialize the initial configuration, turning **ArgoCD** into the central orchestrator for the deployment process and synchronizing all applications on the cluster.

#### App-of-Apps Model and AppProject

_Code reference: [gitops/app-of-apps.yaml](/gitops/app-of-apps.yaml), [gitops/projects/appproject.yaml](/gitops/projects/appproject.yaml)_

The system includes many infrastructure components and training pipelines. If each component is declared independently in ArgoCD, management will become extremely complex as the number of applications increases or when dependencies exist between them. Therefore, the student group applied the **App-of-Apps** design pattern, in which only a single parent application named **k8s-infra-addons** is declared and points to the **gitops/apps/** directory in the Git source code repository. ArgoCD will automatically read the manifests in this directory to create and manage the corresponding child applications.

![App-of-Apps Model](/asset/image/appofapp.png)

In addition, an **AppProject** named **platform** is set up to limit the operational scope of applications. Only allowed repositories and pre-designated namespaces have permission to deploy to the cluster. This mechanism operates independently of Kubernetes' RBAC system, providing an additional layer of control to prevent deployments outside the permitted scope before changes from Git are applied to the actual environment.

![Applications belonging to AppProject platform](/asset/image/platform-scope.png)

#### Automated Bootstrap Process using GitHub Actions

_Code reference: [.github/workflows/](/.github/workflows)_

The bootstrap process is automated via a workflow on GitHub Actions. This workflow uses AWS SSM to execute remote commands on the Bastion Host without opening SSH ports, similar to the Helm bootstrap process presented in the previous section.

First, two foundational manifests, **appproject.yaml** and **app-of-apps.yaml**, are transferred to the Bastion as Base64 and applied using appropriate Kubernetes commands. After the manifests are successfully created, ArgoCD recognizes the parent application and begins syncing configurations from the Git repository.

Next, the workflow triggers the sync process of child applications belonging to the parent application **k8s-infra-addons** and periodically checks for the appearance of child applications within a certain time frame. This mechanism ensures ArgoCD completes the initialization of applications before moving on to the next steps. The applications are then synced in the correct order of their dependencies.

![Bootstrap Process with ArgoCD](/asset/image/argocd-bootstrap.png)

Besides static configurations stored in Git, some parameters are only determined after Terraform completes the infrastructure initialization process, such as IRSA's ARN, Amazon EFS's ID, or the EKS cluster name. Instead of storing these values directly in the Git repository, the workflow reads them from Terraform Outputs and updates them into Application objects via the _kubectl patch_ command. This approach helps separate static configurations from environment-dependent values while maintaining the reusability of the Git repository across multiple different deployment environments.

### Continuous Integration for Multimodal Deep Learning Source Code

_Code reference: [.github/workflows/](/.github/workflows)_

![Continuous Integration for Multimodal Deep Learning Source Code](/asset/image/mul-ci-pipeline-final.png)

The Continuous Integration (CI) process is designed to automate all steps of checking and packaging the multimodal deep learning model source code, ensuring every change pushed to the main branch goes through quality control checks before deployment.

The pipeline is triggered automatically whenever the group pushes the latest source code changes to the GitHub repository. In the first phase, **Job 1** performs static source code analysis using two tools: flake8 and mypy. While flake8 checks for violations in programming design, mypy handles static type checking.

Next, **Job 2** performs Unit Testing with pytest to verify the correctness of critical components such as data preprocessing functions, multimodal feature fusion logic, and evaluation metric calculation functions. Only when all test cases are passed does the pipeline proceed to the next steps.

**Job 3** ensures connection to Amazon ECR - a private Docker image repository on AWS. **Job 4** then executes according to a matrix strategy, parallelizing the Docker image build process and security scanning. The built image is checked by a vulnerability scanning tool to detect CVEs in the dependencies of the training environment. If no issues arise, the image is pushed to ECR, and the new image version is updated in the Helm manifest files at the MLOps infrastructure source code repository.

On the infrastructure side, ArgoCD continuously monitors the Helm manifest repository and automatically syncs the EKS cluster state to the exact declared configuration.

### Deploying Training Pipeline on Argo Workflows

_Code reference: [gitops/mlops-pipeline/isic](/gitops/mlops-pipeline/isic)_

After the CI process of the multimodal deep learning source code is completed and the Docker image containing the entire training environment is pushed to Amazon ECR, Argo Workflows takes that image to execute the multimodal deep learning model training pipeline on the EKS cluster.

Each step in the pipeline is mapped to an independent Kubernetes Pod, allowing computational resource control at a granular level and easily re-executing individual steps when errors occur without having to rerun the entire process. Execution logs of all steps are recorded and stored on Amazon S3 through a bucket named kltn-argo-workflows-logs, serving for future checking and debugging purposes.

The pipeline begins with the **Download data** step, downloading the SLICE-3D 2024 dataset from the storage source to the execution environment. Next, two preprocessing steps are performed in parallel: **Preprocess CSV** processes tabular data, while **Preprocess Image** performs transformations on dermoscopic images. Parallelizing these two flows significantly reduces the total preprocessing time compared to sequential execution.

Results from the two preprocessing branches are merged at the training dataset construction step (_Dataloader and Imbalance Handling_). Here, the system splits the train/val/test sets and applies data imbalance handling techniques to reduce the impact of sample quantity disparities between classes in the dataset.

Next, the operational flow proceeds to build the two components of the multimodal model. For tabular data, an **MLP** network is initialized to extract features from tabular attributes. For image data, the **EfficientNet-B3** model is used as a visual feature extractor. These two model branches are combined during the training phase to form a multimodal deep learning architecture.

After both branches are ready, the **Train** step proceeds to train the unified model with the feature fusion mechanism from the two data streams. During training, evaluation metrics, hyperparameters, and model information are automatically logged to the MLflow Tracking Server.

After completing the training, the model is evaluated on the test dataset through the **Evaluate** step. Finally, the system executes the _XAI (Explainable AI)_ step to analyze and visualize factors influencing the model's prediction decisions.

![Argo Workflow Pipeline on EKS cluster](/asset/image/multimodal-mlops-eks-pipeline.png)

Thanks to being deployed as an Argo Workflow on Kubernetes, the entire process has high reusability, scalability, and automation, while ensuring experiment tracking and model management capabilities.

### Managing and Tracking Training Experiments

_Code reference: [modules/mlflow](/modules/mlflow), [gitops/apps/mlflow.yaml](/gitops/apps/mlflow.yaml)_

To support machine learning model lifecycle management and increase the reproducibility of research results, the student group integrated **MLflow** as a platform for tracking and managing training experiments. **MLflow** allows recording all information related to the training process, including hyperparameters, evaluation metrics, and the execution history of each run.

In the thesis, **MLflow** is deployed on the **Amazon EKS** cluster and integrated directly into the training pipeline. Every time the training process is triggered from **Argo Workflows**, information such as input image size, number of training samples, class weights, execution time, and evaluation metrics will be automatically logged to **MLflow**. This helps minimize manual operations while ensuring consistency in managing experiments.

The figure below illustrates the **MLflow Tracking** interface of the system. The interface displays a list of executed training runs along with related hyperparameters and metrics. Users can access each run to see details of the training process and the resulting model evaluation outcomes.

![Managing experiments on MLflow](/asset/image/mlflow-exp.png)

### Building Model Inference Service with KServe Custom Predictor

_Code reference: [src/model-serving](/src/model-serving)_

To bring the multimodal deep learning model into the operational environment, the group built a custom inference service based on KServe Custom Predictor.

The service is implemented in Python, in which the SkinPredictionModel class inherits from the base class **kserve.Model** and overrides three lifecycle methods: load(), preprocess(), and predict(). Upon initialization, the service automatically downloads inference-serving objects from Amazon S3 via KServe's **Storage Initializer** mechanism.

Upon startup, **load()** reads three artifacts pre-mounted by KServe Storage Initializer from S3 into **/mnt/models**: the .h5 model weights, the encoders.pkl preprocessor set, and the optimal classification threshold best-threshold.txt.

In **preprocess()**, the input image is decoded and passed through the same preprocessing pipeline as the training phase, and tabular data is encoded, imputed, and normalized using transformers pre-integrated in **encoders.pkl**. The **predict()** method then runs inference, applying the optimal threshold instead of the default 0.5, and returns the result along with a GradCAM heatmap if XAI is activated.

The inference service communicates with the outside world adhering to the **KServe V1 Protocol** - an HTTP/JSON standard predefined by KServe, helping the service be compatible with clients independent of specific model frameworks. The user input request is sent to the endpoint **POST /v1/models/skin-prediction:predict** with a payload containing both the dermoscopic image as base64 and clinical information as JSON. The response returns the classification label, prediction probability, inference time, and optional GradCAM heatmap.

![Endpoint of model inference service](/asset/image/api-syntax.png)

### Building Continuous Integration and Continuous Deployment Pipeline for Inference Service

_Code reference: [.github/workflows/](/.github/workflows)_

![Continuous Integration and Continuous Deployment Model for Inference Service](/asset/image/serving-cicd-pipeline.png)

After finalizing the model inference service using **KServe Custom Predictor**, the group proceeded to build a **CI/CD** pipeline to automate the process of deploying new versions of the service to the **Kubernetes** environment. The pipeline is designed based on **GitOps** principles, combining **GitHub Actions**, **Amazon ECR**, **ArgoCD**, and **KServe** to ensure consistency, traceability, and minimize manual deployment operations.

The process begins when the student group updates the inference service source code and pushes the changes to the GitHub source code repository. After the **Pull Request** is created, source code is reviewed and merged into the main branch, **GitHub Actions** will automatically trigger the CI pipeline. In the first phase, the source code of **KServe Custom Predictor** is packaged into a **Docker Image** and pushed to **Amazon ECR**.

After the new image is successfully created, the pipeline moves to the deployment configuration update phase. At this step, **GitHub Actions** automatically replaces the image tag in the **InferenceService** declaration file of **KServe**. Instead of deploying directly to the Kubernetes cluster, the entire desired state of the system is managed as source code, allowing easy control of change history, performing testing, and rolling back when necessary.

**ArgoCD** automatically syncs the desired state down to the **Amazon EKS** cluster. The **KServe Controller** then receives the **InferenceService** resource and performs the creation of necessary components including Service, Deployment, and Pod in **RawDeployment** mode serving model inference.

When the predictor Pod starts, the **storage-initializer** container runs first as an init container, downloading model artifacts from the S3 bucket to the **/mnt/models** directory before the main serving container starts receiving requests. The data flow from S3 to the Pod occurs completely automatically according to the **storageUri** configuration in the manifest, requiring no manual intervention.

After the sync process completes, the inference service is provided through KServe's endpoint and is ready to serve requests from users. The student group uses an API testing tool to send input data and receive prediction results from the model.

![Testing API status](/asset/image/precheck-api.png)

![Testing API response results](/asset/image/post-method-result.png)

### Developing Monitoring and Data Visualization System

_Code reference: [modules/monitoring](/modules/monitoring)_

In an MLOps environment, monitoring does not stop at the model training or deployment process but must also simultaneously observe many different system layers, from the physical state of the Kubernetes cluster, the availability of application services, the progress and cost of the training loop, to the quality of the infrastructure's CI/CD process. An incident occurring at any layer can directly affect the stability of the system. Therefore, the group built a centralized monitoring system based on Prometheus and Grafana to provide comprehensive observability for the MLOps platform.

Data collection is performed automatically using **ServiceMonitor** and **PodMonitor** resources, allowing Prometheus to detect and pull data from **exporters** without manual configuration on each service. Data sources include **kube-state-metrics** and **cAdvisor** serving Kubernetes monitoring, **NVIDIA DCGM Exporter** providing GPU hardware information, **Argo Workflows Controller** tracking training pipelines, ML Pods providing metrics related to the machine learning process, and several **custom exporters** serving infrastructure deployment process monitoring.

![Resource Monitoring and Tracking System](/asset/image/monitoring-and-visualizing.png)

## LIMITATIONS

- Although the MLOps system was built to meet automation and model lifecycle management requirements, the thesis still has some limitations. Due to time and resource constraints, the data and experimental scope are not large enough to comprehensively reflect real-world situations.
- Computational resources are still limited, so experiments and optimizations at a deep and diverse scale cannot be performed yet. In addition, the system has only been verified at an experimental level and has not been fully evaluated in a real-world operating environment at a large scale and over a long period.

## DRAWBACKS

- **Data scale**: only using a small dataset of 10,393 samples out of a total of 401,059 samples (2.6%). Results need to be verified on the entire dataset to evaluate true generalization capability. The objectivity when applying to different skin types in different countries, geographical regions, and races has not been verified.
- **XAI is not stable when serving**: XAI tends to learn artifacts from augmentation instead of true pathological features.
- **pAUC has not reached the target**: pAUC ≈ 0.080 (after normalization) has not reached the threshold of ≥ 0.15 for community screening scenarios. AUC-ROC = 0.892 and F1 = 0.3488 show great potential to be exploited.
- **Malignant Recall = 62%**: there are still 30 Malignant cases missed (FN) on the Test set. In a real clinical environment, this number needs further improvement.
- **Data drift**: this function is only applied in a local environment and has not been brought to the MLOps infrastructure.
- **Continuous learning mechanism has not been built**: the current system only supports automating the process of training, evaluating, and deploying models based on pre-prepared data. A continuous learning mechanism needs to be built to automatically detect new data, retrain the model, and update the serving model version.
- **Limited user audience**: stops at providing API communication ports for testing and integration, has not built an intuitive user interface.

## FUTURE DIRECTIONS

- **Expand data**: train on all 401,059 SLICE-3D samples with distributed infrastructure, expected to significantly improve pAUC and Recall.
- **Upgrade backbone**: test EfficientNetB4/B5, EfficientNetV2, or Vision Transformer (ViT) for the image branch, which may improve image feature quality.
- **Attention mechanism for Fusion**: replace simple Concatenate with Cross-Modal Attention or Transformer-based Fusion so the model learns dynamic interactions between the two modalities.
- **Improve imbalance handling**: integrate Mixup augmentation, CutMix, Asymmetric Loss, or GAN-based oversampling to create high-quality synthetic Malignant samples.
- **Real-world clinical evaluation**: collaborate with medical facilities to collect real-world data, evaluate prospectively on Vietnamese patients - adjusting the model to suit Vietnamese dermatological characteristics.
- **Build continuous learning pipeline**: build an automatic alert mechanism and automatically trigger the model retraining cycle when detecting a severe degradation in input data quality.
- **Build an application**: visualize outputs of the multimodal deep learning model.
- **Federated Learning Application**: privacy-preserving distributed training of patient data across multiple hospitals.

## REFERENCES

- [1]: Centers for Disease Control and Prevention. Skin Cancer Basics. [Online]. Available: https://www.cdc.gov/skin-cancer/about/index.html.[Accessed: Jun. 14, 2026]. July 2024.

- [2]: World Cancer Research Fund International. Skin Cancer. [Online]. Available: https://www.wcrf.org/preventing-cancer/cancer-types/skin-cancer/. [Accessed: Jun. 14, 2026]. 2024.

- [3]: International Agency for Research on Cancer. Non-Melanoma Skin Cancer Fact Sheet. [Online]. Available: https://gco.iarc.who.int/media/globocan/factsheets/cancers/17-non-melanoma-skin-cancer-fact-sheet.pdf. [Accessed: Jun. 14, 2026]. 2024

- [4]: Freddie Bray, Mathieu Laversanne, Hyuna Sung, Jacques Ferlay, Rebecca L. Siegel, Isabelle Soerjomataram, and Ahmedin Jemal. “Global cancer statistics 2022: GLOBOCAN estimates of incidence and mortality worldwide for 36 cancers in 185 countries”. In: CA: A Cancer Journal for Clinicians 74.3 (2024), pp. 229–263. DOI: 10.3322/caac.21834.

- [5]: Tam Anh General Hospital. What is Melanin? Formation mechanism, role and effect. [Online]. Available: https://tamanhhospital.vn/co-the-nguoi/melanin/. [Accessed: Jun. 14, 2026]. Feb. 2026.

- [6]: National Hospital of Dermatology and Venereology. Melanoma Skin Cancer: How to detect it early? [Online]. Available: https://dalieu.vn/ung-thu-da-hac-to-nhanbiet-som-nhu-the-nao-5537.html. [Accessed: Jun. 14, 2026]. Jan. 2026.

- [7]: L. Zhou, Y. Zhong, L. Han, Y. Xie, and M. Wan. “Global, regional, and national trends in the burden of melanoma and non-melanoma skin cancer: Insights from the global burden of disease study 1990–2021”. In: Scientific Reports 15.1 (Feb. 2025), p. 5996. DOI: 10.1038/s41598-025-90485-3.

- [8]: American Academy of Dermatology Association. Types of Skin Cancer. [Online]. Available: https://www.aad.org/public/diseases/skin-cancer/types/common. [Accessed: Jun. 14, 2026]. 2024

- [9]: Cancer Research UK. Types of Non Melanoma Skin Cancer. [Online]. Available: https://www.cancerresearchuk.org/about-cancer/skin-cancer/types. [Accessed: Jun. 14, 2026]. 2024.

- [10]: Mayo Clinic Staff. Melanoma: Symptoms and Causes. [Online]. Available: https://www.mayoclinic.org/diseases-conditions/melanoma/symptoms-causes/syc-20374884. [Accessed: Jun. 14, 2026]. 2023

- [11]: International Skin Imaging Collaboration. ISIC 2024 - Skin Cancer Detection with 3D-TBP. [Online]. Available: https://www.kaggle.com/competitions/ isic-2024-challenge/overview. [Accessed: Jun. 14, 2026]. 2024.
