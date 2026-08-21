#pragma once

#include "audioprovider.hpp"
#if __has_include(<cava/cavacore.h>)
#include <cava/cavacore.h>
#else
struct cava_plan {};
inline cava_plan* cava_init(int, int, int, int, double, double, double) { return nullptr; }
inline void cava_execute(const double*, int, double*, cava_plan*) {}
inline void cava_destroy(cava_plan*) {}
#endif
#include <qqmlintegration.h>

namespace caelestia::services {

class CavaProcessor : public AudioProcessor {
    Q_OBJECT

public:
    explicit CavaProcessor(QObject* parent = nullptr);
    ~CavaProcessor();

    void setBars(int bars);

signals:
    void valuesChanged(QVector<double> values);

protected:
    void process() override;

private:
    struct cava_plan* m_plan;
    double* m_in;
    double* m_out;

    int m_bars;
    QVector<double> m_values;

    void reload();
    void initCava();
    void cleanup();
};

class CavaProvider : public AudioProvider {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int bars READ bars WRITE setBars NOTIFY barsChanged)

    Q_PROPERTY(QVector<double> values READ values NOTIFY valuesChanged)

public:
    explicit CavaProvider(QObject* parent = nullptr);

    [[nodiscard]] int bars() const;
    void setBars(int bars);

    [[nodiscard]] QVector<double> values() const;

signals:
    void barsChanged();
    void valuesChanged();

private:
    int m_bars;
    QVector<double> m_values;

    void updateValues(QVector<double> values);
};

} // namespace caelestia::services
