# Prometheus Alertmanager installer

Features:

* Download latest release
* Install as systemd service
* Uninstaller
* CentOS support
* Debian support

## Additional steps

After install alertmanager you need enable manager in prometheus ( `/etc/prometheus/prometheus.yml` ) config:

```
# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - "localhost:9093"
```

Update web hook URL in alertmanager ( `/etc/alertmanager/alertmanager.yml` ) config:

```
...
receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: '<URL>'
inhibit_rules:
...
```

## Additional tools

Telegram alerting bot:

* https://github.com/m0zgen/prometheus_bot