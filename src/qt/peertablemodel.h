#ifndef PEERTABLEMODEL_H
#define PEERTABLEMODEL_H

#include <QAbstractTableModel>
#include <QStringList>
#include <QTimer>
#include <vector>

#include "net.h"

class ClientModel;

/** Qt table model for connected P2P peers. */
class PeerTableModel : public QAbstractTableModel
{
    Q_OBJECT

public:
    enum ColumnIndex {
        NodeId = 0,
        Address = 1,
        UserAgent = 2,
        Ping = 3,
        NumColumns = 4
    };

    explicit PeerTableModel(ClientModel *parent = 0);
    ~PeerTableModel();

    int rowCount(const QModelIndex &parent = QModelIndex()) const;
    int columnCount(const QModelIndex &parent = QModelIndex()) const;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const;
    QVariant headerData(int section, Qt::Orientation orientation,
                        int role = Qt::DisplayRole) const;
    Qt::ItemFlags flags(const QModelIndex &index) const;

    const CNodeStats *nodeStats(int row) const;
    int getRowByNodeId(int nodeid) const;
    void setRefreshDuringIbd(bool enable);
    void startAutoRefresh();
    void stopAutoRefresh();

public slots:
    void refresh();

private:
    ClientModel *clientModel;
    std::vector<CNodeStats> peers;
    QTimer *timer;
    QStringList columns;
    bool fRefreshing;
    bool fRefreshDuringIbd;
};

#endif // PEERTABLEMODEL_H
