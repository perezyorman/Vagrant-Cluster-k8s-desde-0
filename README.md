# Elaboración de un Cluster de Laboratorio de Kubernetes desde Cero
¡Bienvenido! Este repositorio contiene la documentación detallada y los pasos necesarios para construir un cluster de Kubernetes de forma manual. El objetivo de este proyecto es profundizar en el funcionamiento interno de Kubernetes, moviéndonos más allá de las soluciones automatizadas como kubeadm o servicios gestionados.

⚠️ El Enfoque: "The Hard Way"
Este laboratorio está diseñado para el aprendizaje. No buscamos el camino fácil; buscamos entender la arquitectura, los certificados, la configuración de la red y el plano de control desde sus cimientos.

¿Qué aprenderás?
Configuración de la infraestructura base (VirtualBox/Cloud).

Generación de una infraestructura de PKI (Autoridad de Certificación).

Configuración del almacenamiento etcd.

Despliegue del plano de control (API Server, Scheduler, Controller Manager).

Configuración de los nodos Worker y el runtime de contenedores.

Configuración de la red del cluster (Pod Networking).

# 👨‍💻 Créditos y Referencias Originales
Este proyecto no habría sido posible sin el increíble trabajo previo de la comunidad. Este laboratorio es una adaptación personalizada basada en las siguientes guías maestras:

Kelsey Hightower: Kubernetes The Hard Way - La referencia estándar de la industria para el despliegue en Google Cloud.

Mumshad Mannambeth (KodeKloud): Kubernetes The Hard Way - VirtualBox Edition - Una adaptación excelente para entornos locales usando máquinas virtuales.
