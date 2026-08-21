#pragma once
#include <QtGlobal>
#include <QObject>
#include <QList>

#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
#  include_next <qquickattachedpropertypropagator.h>
#else
class QQuickAttachedPropertyPropagator : public QObject {
public:
    explicit QQuickAttachedPropertyPropagator(QObject* parent = nullptr) : QObject(parent) {}
    void initialize() {}
    QList<QQuickAttachedPropertyPropagator*> attachedChildren() const { return {}; }
protected:
    virtual void attachedParentChange(QQuickAttachedPropertyPropagator* newParent, QQuickAttachedPropertyPropagator* oldParent) {
        Q_UNUSED(newParent);
        Q_UNUSED(oldParent);
    }
};
#endif
