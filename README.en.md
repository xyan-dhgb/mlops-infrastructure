# DESIGN AND IMPLEMENTATION OF AN MLOPS ARCHITECTURE FOR A MULTIMODAL DEEP LEARNING SYSTEM IN SUPPORT OF SKIN CANCER DIAGNOSIS

- English Name: Design and implementation of an MLOps architecture for a multimodal deep learning system to support skin cancer diagnosis

- Advisor: M.Sc. Nguyen Khanh Thuat (thuatnk@uit.edu.vn)

- Team Members:
    - Dinh Huynh Gia Bao (22520101@gm.uit.edu.vn)
    - Tran Gia Bao (22520117@gm.uit.edu.vn)

## PROJECT OVERVIEW

- In recent years, Artificial Intelligence (AI) and deep learning, particularly multimodal models, have been developing rapidly in the field of healthcare.

- They are widely applied to support diagnostic work such as data mining, extracting data from medical images, records and test results. This helps increase accuracy and provides doctors with additional resources in the decision-making process.

- Furthermore, Machine Learning Operations (MLOps) approaches have also been receiving significant attention to automate the process of training, deploying and monitoring models, helping to close the gap between research and practical applications.

- However, medical data often comes from multiple sources with differences in format and continuously changes, making it difficult to integrate and maintain model performance. Additionally, many current deep learning systems still lack automatic deployment, monitoring and retraining procedures, while having to meet strict requirements for traceability, reproducibility and compliance in a medical environment.

## PROPOSED SOLUTION

- After researching the problem, we developed the topic by proposing the development of an MLOps framework for multimodal deep learning systems used in cancer diagnosis.

- The entire machine learning process is essentially considered a software application and can be version controlled, tested and deployed automatically. Additionally, the system is designed with a fully automated training process, combined with model registry to manage and track model versions, performance monitoring systems in the operational environment and GitOps mechanisms for deployment on cloud infrastructure or container orchestration platforms.

- This approach maximizes the level of automation while ensuring the entire model lifecycle can always be traced, reproduced and scaled stably.

![Proposed System](/docs/diagram/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning-4-ml-automation-ci-cd.png)

## PROJECT OBJECTIVES

### General Objective

- The objective of the project is to build an MLOps architecture for multimodal deep learning models, aiming to support the management and automation of the model lifecycle efficiently. The system is oriented towards modern platforms on cloud computing infrastructure, ensuring scalability, stability and sustainable operations.

### Specific Objectives

- **Collect and normalize multi-source datasets:** Build a process to collect, preprocess and normalize data from multiple different data sources (images, text, etc.). Ensure data is stored in a structured form, labeled, quality controlled and easily retrievable for model training and evaluation processes.

- **Build and automate model training pipelines:** Design MLOps pipelines for the process of training, evaluating and deploying multimodal deep learning models. Integrate automation tools to reduce manual operations, ensure experiment reproducibility and shorten model development time.

- **Establish monitoring and retraining mechanisms:** Build systems to monitor model performance after deployment, detect quality degradation (model drift, data drift) and trigger retraining processes when necessary. Ensure the system operates stably and maintains performance over time.

- **Evaluate and verify model results:** Build model evaluation processes based on metrics suitable for the problem, perform testing on independent datasets and compare with existing methods. Ensure model results are reliable, stable and meet practical application requirements.

## IMPLEMENTATION METHODS

### Research and development of multimodal deep learning models

> [!NOTE]
> This section defines data handling strategies and multimodal model architecture design. Given the nature of medical data, preventing data leakage and addressing class imbalance are critical factors.

#### Data Collection and Preprocessing (Data Strategy)

| No. | ATTRIBUTE | CONTENT |
| :--- | :--- | :--- |
| 1 | Full Name | SLICE-3D – Skin Lesion Image Crops Extracted from 3D Total Body Photography |
| 2 | Organization | International Skin Imaging Collaboration (ISIC) |
| 3 | Platform | Kaggle – ISIC 2024 Grand Challenge |
| 4 | Total Samples | 401,059 skin lesion images |
| 5 | Image Size | ~128 × 128 pixel, JPEG format |
| 6 | Metadata Features | 55 columns in train-metadata.csv file |
| 7 | Collection Period | 2015 – 2024 (10 years) |
| 8 | Scientific Publication | Scientific Data, Nature Publishing Group, 2024 |
| 9 | Medical Institutions | 9 hospitals/universities in the USA, Australia, Spain, Austria, Greece, Switzerland |

- 3D Total Body Photography (3D-TBP) technology uses Vectra WB360 equipment (by Canfield Scientific).
    - Performs composite scanning of *92 images* from *46 pairs of stereoscopic cameras*.
    - Applies 3D surface mesh reconstruction algorithm for full-body skin mapping, then automatically detects and extracts lesions as image tiles measuring *15mm×15mm*.

- **Preprocessing and Feature Store:** Images are normalized, resized (to 224×224 or 128×128) and augmented. Tabular data is filled, encoded and normalized using `StandardScaler`. All features are centrally managed through a Feature Store to ensure absolute consistency between the training and production environments.

- **Data Leakage Prevention:** Train/val/test split is performed strictly at the patient level.

#### Multimodal Model Architecture

| No. | ATTRIBUTE | PROPOSED CHOICE | REASON |
| :--- | :--- | :--- | :--- |
| 1 | Image Processing Branch | EfficientNet-B3 (ImageNet pretrained) | Accuracy ~97% ISIC 2024, lightweight, easy to integrate Grad-CAM/XRAI |
| 2 | CSV Processing Branch | MLP (Multi-Layer Perceptron) | Simple late fusion, easy to debug, SHAP explainable |
| 3 | Fusion Layer | Concatenation -> FC -> Dropout (0.3) | Effective late fusion, low overfitting risk |
| 4 | Loss Function | Focal Loss + Class weights | Handles data imbalance (melanoma represents 11%) and optimizes hard examples |
| 5 | XAI Layer | XRAI (region-based) + SHAP for metadata | XRAI superior to Grad-CAM for medical imaging |

#### Explainability (XAI)

> [!NOTE]
> In this MLOps system, model explainability is a critical factor to support doctors in clinical decision-making. We propose using a combination of XRAI for image data and SHAP for metadata.

- **XRAI (eXplanation with Ranked Area Insertions):** XRAI provides intuitive explanations based on lesion regions, rather than focusing only on individual pixels.
    - **Mechanism:** Creates region-based attributions (contributions by region), overcoming the limitations of traditional pixel-level methods like Grad-CAM (often noisy and difficult to read for medical specialists).
    - **Perfect Integration:** Using EfficientNet-B3 + XRAI achieves clear, intuitive and more understandable explanations for doctors.
    - **Superpixels Technique:** XRAI divides the image into superpixels and ranks them by importance. This method is particularly suitable for dermoscopic images as it accurately delineates pathological regions.

- **SHAP (SHapley Additive exPlanations):** SHAP is integrated to explain the impact of non-image factors (metadata) on the final prediction result.
    - **Main Role:** Uses SHAP to quantify the contribution of each metadata attribute (such as age, lesion location, gender...) to cancer probability prediction.

#### Evaluation Metrics

- Performance evaluation on the test set uses metrics: Accuracy, Precision, Recall, F1-score (macro and weighted), AUC-ROC for each class, and Confusion Matrix for detailed analysis.

### Build infrastructure to deploy multimodal deep learning models

> [!NOTE]
> The Ops system is built on a cloud-native platform, with automation from source code integration, training to monitoring and model distribution.

- **Infrastructure as Code (IaC):** The entire infrastructure including Kubernetes cluster (AWS EKS), Object Storage (S3), and Container Registry (AWS ECR) is defined and deployed through code via Terraform.

- **CI/CD Pipeline for multimodal deep learning models:** Build an automated pipeline for the entire process from data collection to model deployment. Use tools such as `GitHub Actions` to manage versions and automate CI/CD, and `MLflow` to orchestrate workflows and manage the model lifecycle. Each source code commit triggers an automated testing process (including unit tests and integration tests), model training on a data subset to verify code correctness, and automated model evaluation.

- **CI/CD Pipeline Metrics:** pipeline execution time (time from commit to pipeline completion), pipeline success rate (percentage of successful pipeline runs), automated test pass rate (percentage of tests passed) and model performance stability (consistency of metrics like accuracy or F1-score between training runs).

#### MLOps Infrastructure Deployment

> [!NOTE]
> This phase aims to build a cloud-native infrastructure foundation for the entire MLOps system, ensuring scalability, high availability, automation and environment reproducibility. Specifically, the main objectives include:

* **Deploy Kubernetes Cluster:** Use **Amazon EKS** (Elastic Kubernetes Service) as the container orchestration platform to manage services and pipelines.
* **Apply Terraform:** Define and deploy infrastructure as code (**Infrastructure as Code - IaC**) to ensure automation and synchronization.
* **Deploy Object Storage:** Use storage services (such as Amazon S3) to store data, model artifacts and logs.
* **Set up Container Registry:** Use **Amazon ECR** to manage and store Docker images.
* **Deploy MLflow Tracking Server:** Manage the model lifecycle, track experiments and training parameters.
* **Configure Git Repository:** Use as the centralized source control management.
* **Configure CI Pipeline:** Use **GitHub Actions** to automate the continuous integration process.
* **Deploy ArgoCD:** Manage application deployment to Kubernetes using **GitOps** model, ensuring cluster state is always consistent with Git configuration.

#### Build CI/CD Pipeline

> [!NOTE]
> This phase aims to build a data processing and machine learning model development process that is reproducible, traceable and automated. Specifically, objectives include:

* **Build CI/CD Pipeline:** Combine automated pipeline architecture with **GitOps** model to optimize deployment.
* **Centralized Source Code Management:** All pipeline source code, infrastructure configuration (IaC) and deployment components are stored and managed on **GitHub**.
* **Automatic CI Trigger:** The system automatically triggers CI (Continuous Integration) when source code changes, performs testing (Unit Tests), builds Docker image and packages components for model training/deployment.
* **Docker Image Management:** Push successfully built Docker images to **Container Registry** (such as Amazon ECR) for use in different deployment environments.
* **Deploy CD with GitOps Model:** The desired system state is defined using **K8s manifest** files or **Helm charts** stored in the repository.
* **Automatic Synchronization:** The system automatically synchronizes configuration from the repository into the **Kubernetes** cluster to deploy new or update pipelines and model serving services without manual intervention.

#### Monitoring and Results Logging

> [!NOTE]
> This phase aims to establish comprehensive monitoring mechanisms for the MLOps system and evaluate model effectiveness in real-world environments. Main objectives include: Monitoring the operational status of the system and model services.

* **Deploy Two-Layer Monitoring System:** Establish comprehensive monitoring mechanisms including both Infrastructure Monitoring and Model Monitoring.
* **Visualize Infrastructure Metrics:** Collect and monitor real-time technical parameters such as CPU, memory (RAM), latency and request count of inference services.
* **Monitor Data and Models:** Control model input and output data to detect timely phenomena such as **Data Drift** (changes in data distribution over time).
* **Trigger Automatic Retraining:** The system automatically triggers the training pipeline (re-training) when quality degradation or model performance decline is detected.

![Deployment System](/docs/diagram/sketching%20system.png)

## PROJECT LIMITATIONS

- Although the MLOps system is built to meet requirements for automation and model lifecycle management, the project still has some limitations. Due to time and resource constraints, the data and scope of experiments are not yet large enough to comprehensively reflect real-world situations.

- Computing resources are still limited so we cannot yet conduct extensive and diverse experiments and optimization. Additionally, the system has only been verified at the experimental level, without complete evaluation in real operational environments at large scale and over long periods.

## REFERENCES

- [1] G Mallardi, L Quaranta, et al. "MLOps in the Healthcare Domain: a Systematic Literature Review". In: Software Engineering and Advanced Applications. SEAA 2025. Vol. 16082. Lecture Notes in Computer Science. [Online; accessed 2025]. Cham: Springer, 2026. URL: https://link.springer.com/chapter/10.1007/978-3-032-04200-2%5C_23.

- [2] P. Rajpurkar, E. Chen, et al. "AI in health and medicine". In: Nature Medicine 28.1 (2022), pp. 31-38. ISSN: 1546-170X. DOI: https://doi.org/10.1038/s41591-021-01614-0.

- [3] Oracle. 10 Healthcare Challenges to Solve in 2026. [Online; accessed 2026]. 2026. URL: https://www.oracle.com/health/healthcare-challenges/.

- [4] K Mustafa M Shan. Driving Innovation in AI/ML Healthcare with Scalable AI Workflows MLOps and Cloud-Based Data Engineering. [Online; accessed 2025]. 2025. URL: https://www.researchgate.net/publication/390090254.

- [5] Mehdi Mahdavi. Skin Cancer (PAD-UFES-20). https://www.kaggle.com/datasets/mahdavi1202/skin-cancer. Accessed: 2026-03-05. 2022.

- [6] A Kumar Singh et al. "Using Multimodal Biometrics, Data Hiding, and Encryption for Secure Healthcare Imaging System". In: IET Image Processing (2024). [Online; accessed 2024]. URL: https://ieeexplore.ieee.org/document/10623370.

- [7] Google Cloud. MLOps: Continuous Delivery and Automation Pipelines in Machine Learning. [Online; accessed 2021]. 2021. URL: https://cloud.google.com/architecture/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning.

- [8] Berkman Sahiner, Weijie Chen, et al. "Data Drift in Medical Machine Learning: Implications and Potential Remedies". In: The British Journal of Radiology 96.1150 (2023). [Online; accessed 2023], p. 20220878. URL: https://academic.oup.com/bjr/article/96/1150/7499000.
