# Usar Ubuntu como base
FROM debian:stable-slim

# Actualizar paquetes e instalar dnsmasq
RUN apt-get update && apt-get install -y dnsmasq && rm -rf /var/lib/apt/lists/*

# Copiar archivo de configuración personalizado
COPY dnsmasq.conf /etc/dnsmasq.conf

# Exponer puertos
EXPOSE 5353/udp 5353/tcp

# Comando para iniciar dnsmasq en primer plano
CMD ["dnsmasq", "-k"]
