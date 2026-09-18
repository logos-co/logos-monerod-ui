#include "MonerodBackend.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>

namespace {
constexpr int kPollMs = 2000;
constexpr int kStartTimeoutMs = 30000;
constexpr int kStopTimeoutMs = 30000;  // a syncing node takes seconds to wind down
constexpr int kLogLines = 80;

QString toJson(const QVariantMap& m) {
    return QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(m)).toJson(QJsonDocument::Compact));
}
QString describe(const QString& e) { return e.isEmpty() ? QStringLiteral("unknown error") : e; }
QString describe(const logos::CallError& e) { return describe(QString::fromStdString(e.message)); }

// monerod lines are "date time\tthread\tlevel\tcategory\tfile:line\tmessage"; keep time, level, message.
QString compactLog(const QString& raw) {
    QStringList out;
    for (const QString& line : raw.split(u'\n')) {
        const QStringList f = line.split(u'\t');
        if (f.size() < 6 || f[0].size() < 12) { out << line; continue; }
        out << f[0].mid(11) + QStringLiteral("  ") + f[2].trimmed().leftJustified(5)
                 + QStringLiteral("  ") + f.mid(5).join(u' ').trimmed();
    }
    return out.join(u'\n');
}
}

MonerodBackend::MonerodBackend(QObject* parent) : MonerodBackendSimpleSource(parent) {
    setNetwork(QStringLiteral("stagenet"));
}

void MonerodBackend::onContextReady() {
    m_logos = new LogosModules(modules().api);
    m_poll = new QTimer(this);
    m_poll->setInterval(kPollMs);
    connect(m_poll, &QTimer::timeout, this, [this] { poll(); });
    m_poll->start();
    loadConfig();
    poll();
}

void MonerodBackend::poll() {
    if (!m_logos) return;
    m_logos->monerod_module.statusAsyncResult([this](logos::AsyncResult<QVariantMap> r) {
        if (!r.ok()) { setState(QStringLiteral("unavailable")); return; }
        setState(r.value.value("state").toString());
        setStatusJson(toJson(r.value));
        const QString running = r.value.value("network").toString();
        if (!running.isEmpty() && r.value.value("state").toString() != QLatin1String("stopped")
            && running != network()) {
            setNetwork(running);  // show the node that is actually running
            loadConfig();
        }
    });
    m_logos->monerod_module.logTailAsyncResult(kLogLines, [this](logos::AsyncResult<QString> r) {
        if (r.ok()) setLogText(compactLog(r.value));
    });
}

void MonerodBackend::loadConfig() {
    if (!m_logos) return;
    m_logos->monerod_module.getConfigAsyncResult(network(), [this](logos::AsyncResult<QVariantMap> r) {
        if (r.ok()) setConfigJson(toJson(r.value));
    });
}

void MonerodBackend::selectNetwork(QString n) {
    if (n == network()) return;
    setNetwork(n);
    setLastError({});
    loadConfig();
}

void MonerodBackend::saveConfig(QString configJson) {
    if (!m_logos) return;
    const QVariantMap cfg = QJsonDocument::fromJson(configJson.toUtf8()).object().toVariantMap();
    m_logos->monerod_module.configureAsyncResult(network(), cfg, [this](logos::AsyncResult<LogosResult> r) {
        if (!r.ok()) { setLastError(describe(r.error)); return; }
        if (!r.value.success) { setLastError(describe(r.value.error.toString())); return; }
        setLastError({});
        setConfigJson(toJson(r.value.value.toMap()));
    });
}

void MonerodBackend::start() {
    if (!m_logos || busy()) return;
    setBusy(true);
    setLastError({});
    m_logos->monerod_module.startAsyncResult(network(), [this](logos::AsyncResult<LogosResult> r) {
        setBusy(false);
        if (!r.ok()) setLastError(describe(r.error));
        else if (!r.value.success) setLastError(describe(r.value.error.toString()));
        poll();
    }, Timeout(kStartTimeoutMs));
}

void MonerodBackend::stop() {
    if (!m_logos || busy()) return;
    setBusy(true);
    m_logos->monerod_module.stopAsyncResult([this](logos::AsyncResult<LogosResult> r) {
        setBusy(false);
        if (!r.ok()) setLastError(describe(r.error));
        poll();
    }, Timeout(kStopTimeoutMs));
}

void MonerodBackend::refresh() { poll(); }
