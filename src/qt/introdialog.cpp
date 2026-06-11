#include "introdialog.h"
#include "ui_introdialog.h"
#include "guiutil.h"

#include "util.h"

#include <QFileDialog>
#include <QMessageBox>
#include <QSettings>
#include <QStorageInfo>

IntroDialog::IntroDialog(QWidget *parent) :
    QDialog(parent),
    ui(new Ui::IntroDialog),
    fOverriddenDir(false)
{
    ui->setupUi(this);
    setDataDirectory(GUIUtil::getDefaultDataDir());
}

IntroDialog::~IntroDialog()
{
    delete ui;
}

QString IntroDialog::getDataDirectory() const
{
    return dataDir;
}

bool IntroDialog::pickDataDirectory()
{
    if (!GUIUtil::needChooseDataDirectory())
        return true;

    IntroDialog dialog;
    if (dialog.exec() != QDialog::Accepted)
        return false;

    const QString dir = dialog.getDataDirectory();
    if (dir.isEmpty())
        return false;

    mapArgs["-datadir"] = dir.toStdString();

    bool testnet = GetBoolArg("-testnet", false);
    QSettings settings("InfiniteRicks", testnet ? "InfiniteRicks-Qt-testnet" : "InfiniteRicks-Qt");
    settings.setValue("strDataDir", dir);

    return true;
}

void IntroDialog::setDataDirectory(const QString &dir)
{
    dataDir = GUIUtil::expandDataDirPath(dir);
    ui->dataDirectory->setText(dataDir);
    ui->errorLabel->clear();

    QStorageInfo storage(dataDir);
    if (storage.isValid() && storage.isReady()) {
        ui->storageLabel->setText(tr("Available storage space: %1").arg(
            GUIUtil::formatBytes(storage.bytesAvailable())));
    } else {
        ui->storageLabel->setText(tr("Available storage space: calculating..."));
    }
}

bool IntroDialog::verifyAndSetDataDirectory(const QString &dir)
{
    QString path = GUIUtil::expandDataDirPath(dir);
    if (path.isEmpty()) {
        ui->errorLabel->setText(tr("Invalid data directory."));
        return false;
    }

    boost::filesystem::path fsPath(path.toStdString());
    if (boost::filesystem::exists(fsPath) && !boost::filesystem::is_directory(fsPath)) {
        ui->errorLabel->setText(tr("The chosen directory is not a folder."));
        return false;
    }

    setDataDirectory(path);
    return true;
}

void IntroDialog::on_dataDirectory_textEdited(const QString &arg1)
{
    fOverriddenDir = true;
    verifyAndSetDataDirectory(arg1);
}

void IntroDialog::on_browseButton_clicked()
{
    QString dir = GUIUtil::getExistingDirectory(this, tr("Choose data directory"), dataDir);
    if (!dir.isEmpty()) {
        fOverriddenDir = true;
        verifyAndSetDataDirectory(dir);
    }
}

void IntroDialog::on_okButton_clicked()
{
    if (!verifyAndSetDataDirectory(ui->dataDirectory->text()))
        return;

    boost::filesystem::path path(dataDir.toStdString());
    try {
        boost::filesystem::create_directories(path);
    } catch (const boost::filesystem::filesystem_error &) {
        ui->errorLabel->setText(tr("Could not create the data directory."));
        return;
    }

    accept();
}
