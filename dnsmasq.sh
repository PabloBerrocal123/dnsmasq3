#!/bin/bash
set -euo pipefail

# Configuración
DOCKER_IMAGE="mi-dnsmasq"
DOCKER_CONTAINER="dnsmasq-5354"
DNSMASQ_CONFIG="/etc/dnsmasq.conf"
DOMAIN_LIST="/etc/dnsmasq.d/dominios.conf"
PLAYBOOK_PATH="install_dnsmasq.yml"

RED='\033[0m'
GREEN='\033[0m'
YELLOW='\033[0m'
NC='\033[0m'

# Función para mostrar errores y salir
mostrar_error_y_salir() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

# Comprobar estado de dnsmasq
comprobar_estado_dnsmasq() {
    if ! dpkg -s dnsmasq &>/dev/null; then
        echo -e "${YELLOW}dnsmasq NO está instalado.${NC}"
        return 1
    fi

    if systemctl list-unit-files 'dnsmasq.service' | grep -q 'dnsmasq.service'; then
        if systemctl is-active dnsmasq >/dev/null 2>&1; then
            echo -e "${GREEN}dnsmasq está corriendo${NC}"
            return 0
        else
            echo -e "${YELLOW}dnsmasq está instalado (nativo) pero detenido.${NC}"
            return 2
        fi
    else
        echo -e "${YELLOW}dnsmasq instalado pero el servicio no está registrado en systemd.${NC}"
        return 3
    fi
}


# Función: Comprobar el estado de dnsmasq en Docker
comprobar_estado_dnsmasq_docker() {
    if docker ps --filter "name=$DOCKER_CONTAINER" --format "{{.Names}}" | grep -q "$DOCKER_CONTAINER"; then
        echo -e "${GREEN}dnsmasq está corriendo en Docker.${NC}"
        return 0
    elif docker ps -a --filter "name=$DOCKER_CONTAINER" --format "{{.Names}}" | grep -q "$DOCKER_CONTAINER"; then
        echo -e "${YELLOW}dnsmasq está en Docker pero el contenedor está detenido.${NC}"
        return 2
    elif docker images -q "$DOCKER_IMAGE" &>/dev/null; then
        echo -e "${YELLOW}dnsmasq está en Docker como imagen, pero no hay contenedor creado.${NC}"
        return 3
    else
        echo -e "${RED}dnsmasq NO está instalado en Docker.${NC}"
        return 1
    fi
}


# Mostrar datos de red
mostrar_datos_red() {
    echo -e "\n=== ${GREEN}DATOS DE RED${NC} ==="
    ip -c addr show 2>/dev/null || ifconfig 2>/dev/null || echo "No se pudo obtener información de red."
    echo -e "============================="
}

# Mostrar estado del servicio
mostrar_estado_servicio() {
    echo -e "\n=== ${GREEN}ESTADO DEL SERVICIO (dnsmasq)${NC} ==="
    comprobar_estado_dnsmasq || true
    echo -e "====================================="
}

# Instalar dnsmasq con comandos
instalar_con_comandos() {
    echo -e "${GREEN}Instalando dnsmasq${NC}"
    sudo apt-get update || mostrar_error_y_salir "Error al actualizar paquetes."
    sudo apt-get install -y dnsmasq || mostrar_error_y_salir "Error al instalar dnsmasq."
    
    sudo systemctl daemon-reload
    sudo systemctl enable dnsmasq || mostrar_error_y_salir "Error al habilitar dnsmasq."
    sudo systemctl start dnsmasq || mostrar_error_y_salir "Error al iniciar dnsmasq."
    
    echo -e "${GREEN}dnsmasq instalado correctamente.${NC}"
}


# Función: Instalar dnsmasq con Docker (usando una imagen existente)
instalar_con_docker() {
    echo -e "${GREEN}Instalando dnsmasq en Docker...${NC}"

    # Usar una imagen existente de Docker Hub
    DOCKER_IMAGE="andyshinn/dnsmasq"

    # Descargar la imagen si no está disponible localmente
    if ! docker images -q "$DOCKER_IMAGE:latest" &>/dev/null; then
        echo -e "${YELLOW}Descargando la imagen '$DOCKER_IMAGE:latest' desde Docker Hub...${NC}"
        docker pull "$DOCKER_IMAGE:latest" || {
            echo -e "${RED}Error: No se pudo descargar la imagen '$DOCKER_IMAGE:latest'.${NC}"
            echo -e "${YELLOW}Verifica que la imagen existe en Docker Hub y que tienes acceso a Internet.${NC}"
            return 1
        }
    fi

    # Crear y ejecutar el contenedor
    echo -e "${GREEN}Creando el contenedor...${NC}"
    docker run -d --name "$DOCKER_CONTAINER" -p 5354:5354/udp -p 5354:5354/tcp "$DOCKER_IMAGE:latest" || {
        echo -e "${RED}Error al crear el contenedor.${NC}"
        return 1
    }

    echo -e "${GREEN}dnsmasq instalado correctamente en Docker.${NC}"
}


# Función: Instalar dnsmasq con Ansible
instalar_con_ansible() {
    echo -e "${GREEN}Instalando dnsmasq con Ansible...${NC}"

    # Verificar si Ansible está instalado
    if ! command -v ansible-playbook &>/dev/null; then
        echo -e "${YELLOW}Ansible no está instalado. Instalando Ansible...${NC}"
        sudo apt-get update || mostrar_error_y_salir "Error al actualizar paquetes."
        sudo apt-get install -y ansible || mostrar_error_y_salir "Error al instalar Ansible."
    fi

    # Verificar si el playbook existe
    if [ ! -f "$PLAYBOOK_PATH" ]; then
        echo -e "${RED}El playbook '$PLAYBOOK_PATH' no existe.${NC}"
        echo -e "${YELLOW}Asegúrate de que el playbook esté en el directorio correcto.${NC}"
        return 1
    fi

    # Ejecutar el playbook
    echo -e "${GREEN}Ejecutando el playbook...${NC}"
    ansible-playbook "$PLAYBOOK_PATH" || mostrar_error_y_salir "Error al ejecutar el playbook de Ansible."
    echo -e "${GREEN}dnsmasq instalado correctamente con Ansible.${NC}"
}


# Eliminar dnsmasq
eliminar_servicio() {
    if dpkg -s dnsmasq &>/dev/null; then
        echo -e "${YELLOW}Deteniendo y eliminando dnsmasq...${NC}"
        sudo systemctl stop dnsmasq || true
        sudo systemctl disable dnsmasq || true
        sudo apt-get purge -y dnsmasq || mostrar_error_y_salir "Error al eliminar dnsmasq."
        sudo rm -f "$DOMAIN_LIST" 2>/dev/null || true
        echo -e "${GREEN}dnsmasq eliminado correctamente.${NC}"
    else
        echo -e "${YELLOW}dnsmasq no está instalado.${NC}"
    fi
}


# Función: Eliminar el servicio en Docker
eliminar_servicio_docker() {
    echo -e "${YELLOW}Deteniendo y eliminando el contenedor...${NC}"
    docker stop "$DOCKER_CONTAINER" 2>/dev/null || true
    docker rm "$DOCKER_CONTAINER" 2>/dev/null || true
    echo -e "${GREEN}Contenedor eliminado.${NC}"

    read -p "¿Desea eliminar también la imagen Docker? (s/n): " opcion_elim
    if [[ "$opcion_elim" =~ ^[sS] ]]; then
        docker rmi "$DOCKER_IMAGE:latest" 2>/dev/null && echo -e "${GREEN}Imagen eliminada.${NC}" || echo -e "${RED}No había imagen para eliminar.${NC}"
    fi
}


# Gestionar el servicio
gestionar_servicio() {
    echo -e "\n=== ${GREEN}GESTIÓN DEL SERVICIO${NC} ==="
    echo "1  Iniciar"
    echo "2  Detener"
    echo "3  Reiniciar"
    echo "4  Estado"
    read -p "Seleccione una opción: " opcion

    if dpkg -s dnsmasq &>/dev/null; then
        case $opcion in
            1) 
                sudo systemctl start dnsmasq && echo -e "${GREEN}Servicio iniciado.${NC}" || echo -e "${RED}Error al iniciar.${NC}"
                ;;
            2) 
                sudo systemctl stop dnsmasq && echo -e "${GREEN}Servicio detenido.${NC}" || echo -e "${RED}Error al detener.${NC}"
                ;;
            3) 
                sudo systemctl restart dnsmasq && echo -e "${GREEN}Servicio reiniciado.${NC}" || echo -e "${RED}Error al reiniciar.${NC}"
                ;;
            4) 
                echo -e "\n=== ${GREEN}ESTADO DEL SERVICIO${NC} ==="
                sudo systemctl status dnsmasq --no-pager || true
                ;;
            *) 
                echo -e "${RED}Opción inválida.${NC}" 
                ;;
        esac
    else
        echo -e "${RED}dnsmasq no está instalado.${NC}"
    fi
}

# Función: Gestionar el servicio en Docker
gestionar_servicio_docker() {
    echo -e "\n=== ${GREEN}GESTIÓN DEL SERVICIO (Docker)${NC} ==="
    echo "1  Iniciar"
    echo "2  Detener"
    echo "3  Reiniciar"
    echo "4  Estado"
    read -p "Seleccione una opción: " opcion

    case "$opcion" in
        1)
            docker start "$DOCKER_CONTAINER" && echo -e "${GREEN}Contenedor iniciado.${NC}" || echo -e "${RED}Error al iniciar.${NC}"
            ;;
        2)
            docker stop "$DOCKER_CONTAINER" && echo -e "${GREEN}Contenedor detenido.${NC}" || echo -e "${RED}Error al detener.${NC}"
            ;;
        3)
            docker restart "$DOCKER_CONTAINER" && echo -e "${GREEN}Contenedor reiniciado.${NC}" || echo -e "${RED}Error al reiniciar.${NC}"
            ;;
        4)
            echo -e "\n=== ${GREEN}ESTADO DEL CONTENEDOR${NC} ==="
            docker ps --filter "name=$DOCKER_CONTAINER" --format "ID: {{.ID}}, Estado: {{.Status}}" || echo -e "${RED}El contenedor no está en ejecución.${NC}"
            ;;
        *)
            echo -e "${RED}Opción inválida.${NC}"
            ;;
    esac
}

# Consultar registros
consultar_registros() {
    echo -e "\n=== ${GREEN}CONSULTAR REGISTROS${NC} ==="
    echo "1) Por fecha (hoy)"
    echo "2) Por tipo (errores)"
    echo "3) Completos"
    read -p "Seleccione una opción: " opcion_reg

    if dpkg -s dnsmasq &>/dev/null; then
        case "$opcion_reg" in
            1)
                echo -e "\n=== REGISTROS DE HOY ==="
                sudo journalctl -u dnsmasq --since today --no-pager || echo "No hay registros para hoy."
                ;;
            2)
                echo -e "\n=== REGISTROS DE ERRORES ==="
                sudo journalctl -u dnsmasq --no-pager | grep -i "error" || echo "No hay errores en los registros."
                ;;
            3)
                echo -e "\n=== REGISTROS COMPLETOS ==="
                sudo journalctl -u dnsmasq --no-pager || echo "Error al consultar registros."
                ;;
            *)
                echo -e "${RED}Opción no válida.${NC}"
                ;;
        esac
    else
        echo -e "${RED}dnsmasq no está instalado.${NC}"
    fi
}


# Función: Consultar registros en Docker
consultar_registros_docker() {
    echo -e "\n=== ${GREEN}CONSULTAR REGISTROS (Docker)${NC} ==="
    echo "1) Por fecha (hoy)"
    echo "2) Por tipo (errores)"
    echo "3) Completos"
    read -p "Seleccione una opción: " opcion_reg

    case "$opcion_reg" in
        1)
            echo -e "\n=== REGISTROS DE HOY ==="
            docker logs "$DOCKER_CONTAINER" --since "$(date +'%Y-%m-%d')" 2>/dev/null || echo -e "${RED}No hay registros para hoy.${NC}"
            ;;
        2)
            echo -e "\n=== REGISTROS DE ERRORES ==="
            docker logs "$DOCKER_CONTAINER" 2>/dev/null | grep -i "error" || echo -e "${RED}No hay errores en los registros.${NC}"
            ;;
        3)
            echo -e "\n=== REGISTROS COMPLETOS ==="
            docker logs "$DOCKER_CONTAINER" 2>/dev/null || echo -e "${RED}Error al consultar registros.${NC}"
            ;;
        *)
            echo -e "${RED}Opción no válida.${NC}"
            ;;
    esac
}


# Editar configuración
editar_configuracion() {
    if dpkg -s dnsmasq &>/dev/null; then
        echo -e "${GREEN}Creando copia de seguridad de la configuración...${NC}"
        sudo cp "$DNSMASQ_CONFIG" "${DNSMASQ_CONFIG}.bak"
        sudo nano "$DNSMASQ_CONFIG"
        echo -e "${GREEN}Reiniciando servicio para aplicar cambios...${NC}"
        sudo systemctl restart dnsmasq || echo -e "${RED}Error al reiniciar el servicio.${NC}"
    else
        echo -e "${RED}dnsmasq no está instalado.${NC}"
    fi
}


# Función: Editar configuración en Docker
editar_configuracion_docker() {
    echo -e "${GREEN}Editando configuración dentro del contenedor...${NC}"

    # Verificar si el contenedor está en ejecución
    if ! docker ps --filter "name=$DOCKER_CONTAINER" --format "{{.Names}}" | grep -q "$DOCKER_CONTAINER"; then
        echo -e "${RED}El contenedor no está en ejecución. Inicia el contenedor primero.${NC}"
        return 1
    fi

    # Copiar el archivo de configuración fuera del contenedor
    TEMP_FILE=$(mktemp)
    docker cp "$DOCKER_CONTAINER:$DNSMASQ_CONFIG" "$TEMP_FILE" || {
        echo -e "${RED}Error al copiar la configuración desde el contenedor.${NC}"
        return 1
    }

    # Editar el archivo localmente
    nano "$TEMP_FILE" || {
        echo -e "${RED}Error al editar la configuración.${NC}"
        return 1
    }

    # Copiar el archivo editado de vuelta al contenedor
    docker cp "$TEMP_FILE" "$DOCKER_CONTAINER:$DNSMASQ_CONFIG" || {
        echo -e "${RED}Error al copiar la configuración al contenedor.${NC}"
        return 1
    }

    # Reiniciar el contenedor para aplicar los cambios
    docker restart "$DOCKER_CONTAINER" && echo -e "${GREEN}Contenedor reiniciado para aplicar cambios.${NC}" || {
        echo -e "${RED}Error al reiniciar el contenedor.${NC}"
        return 1
    }

    # Limpiar el archivo temporal
    rm -f "$TEMP_FILE"
}


# Gestión de dominios
gestion_dominios() {
    if ! dpkg -s dnsmasq &>/dev/null; then
        echo -e "${RED}dnsmasq no está instalado.${NC}"
        return
    fi

    echo -e "\n=== ${GREEN}GESTIÓN DE DOMINIOS${NC} ==="
    echo "1  Añadir dominio"
    echo "2  Eliminar dominio"
    echo "3  Listar dominios"
    read -p "Seleccione una opción: " opcion

    case $opcion in
        1)
            read -p "Introduzca el dominio (ejemplo.com): " dominio
            read -p "Introduzca la IP asociada: " ip
            echo "address=/$dominio/$ip" | sudo tee -a "$DOMAIN_LIST" >/dev/null
            sudo systemctl restart dnsmasq && echo -e "${GREEN}Dominio añadido.${NC}" || echo -e "${RED}Error al reiniciar el servicio.${NC}"
            ;;
        2)
            if [ ! -f "$DOMAIN_LIST" ]; then
                echo -e "${RED}No hay dominios registrados.${NC}"
                return
            fi
            echo -e "\nDominios registrados:"
            nl "$DOMAIN_LIST"
            read -p "Introduzca el número de línea a eliminar: " linea
            sudo sed -i "${linea}d" "$DOMAIN_LIST"
            sudo systemctl restart dnsmasq && echo -e "${GREEN}Dominio eliminado.${NC}" || echo -e "${RED}Error al reiniciar el servicio.${NC}"
            ;;
        3)
            if [ -f "$DOMAIN_LIST" ]; then
                echo -e "\n=== ${GREEN}DOMINIOS REGISTRADOS${NC} ==="
                cat "$DOMAIN_LIST"
            else
                echo -e "${RED}No hay dominios registrados.${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Opción inválida.${NC}"
            ;;
    esac
}

# Menú principal
mostrar_menu_principal() {
    clear
    mostrar_datos_red
    mostrar_estado_servicio
    echo -e "\n=== ${GREEN}MENÚ PRINCIPAL${NC} ==="
    echo "1  Instalación del servicio"
    echo "   a) Con comandos"
    echo "   b) Con Docker"
    echo "   c) Con Ansible"
    echo "2  Eliminar el servicio"
    echo "   a) Eliminar instalación"
    echo "   b) Eliminar contenedor Docker"
    echo "3  Gestionar el servicio"
    echo "   a) Gestionar servicio"
    echo "   b) Gestionar contenedor Docker"
    echo "4  Consultar registros"
    echo "   a) Registros del servicio"
    echo "   b) Registros del contenedor Docker"
    echo "5  Editar configuración"
    echo "   a) Editar configuración"
    echo "   b) Editar configuración en Docker"
    echo "6  Gestión de dominios"
    echo "0  Salir"
    read -p "Seleccione una opción: " opcion
}

# Ejecución principal
while true; do
    mostrar_menu_principal
    case "$opcion" in
        1a) instalar_con_comandos ;;
        1b) instalar_con_docker ;;
        1c) instalar_con_ansible ;;
        2a) eliminar_servicio ;;
        2b) eliminar_servicio_docker ;;
        3a) gestionar_servicio ;;
        3b) gestionar_servicio_docker ;;
        4a) consultar_registros ;;
        4b) consultar_registros_docker ;;
        5a) editar_configuracion ;;
        5b) editar_configuracion_docker ;;
        6) gestion_dominios ;;
        0) echo -e "${GREEN}Saliendo...${NC}" ; exit 0 ;;
        *) echo -e "${RED}Opción no válida.${NC}" ;;
    esac
    read -p "Presione Enter para continuar..."
done
