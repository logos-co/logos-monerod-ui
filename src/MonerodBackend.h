#pragma once

#include "logos_api.h"
#include "logos_sdk.h"
#include "logos_ui_plugin_context.h"
#include "rep_MonerodBackend_source.h"

#include <QTimer>

class MonerodBackend : public MonerodBackendSimpleSource, public LogosUiPluginContext {
    Q_OBJECT
public:
    explicit MonerodBackend(QObject* parent = nullptr);

    void selectNetwork(QString network) override;
    void saveConfig(QString configJson) override;
    void start() override;
    void stop() override;
    void refresh() override;

protected:
    void onContextReady() override;

private:
    void poll();
    void loadConfig();

    LogosModules* m_logos = nullptr;
    QTimer* m_poll = nullptr;
};
