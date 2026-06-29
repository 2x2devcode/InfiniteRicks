#include "introdialog.h"
#include "ui_introdialog.h"
#include "guiutil.h"

#include "util.h"

#include <QFile>
#include <QFileDialog>
#include <QSettings>
#include <QStorageInfo>

#include <boost/filesystem.hpp>

IntroDialog::IntroDialog(QWidget *parent) :
    QDialog(parent),
    ui(new Ui::IntroDialog),
    fOverriddenDir(false)
{
    ui->setupUi(this);
    setDataDirectory(GUIUtil::getDefaultDataDir());
    updateBootstrapWidgets(false);
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

void IntroDialog::updateBootstrapWidgets(bool enabled)
{
    ui->bootstrapFile->setEnabled(enabled);
    ui->browseBootstrapButton->setEnabled(enabled);
    ui->bootstrapHintLabel->setEnabled(enabled);
    if (!enabled) {
        bootstrapFile.clear();
        ui->bootstrapFile->clear();
    }
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

void IntroDialog::on_bootstrapCheckBox_toggled(bool checked)
{
    updateBootstrapWidgets(checked);
    ui->errorLabel->clear();
}

void IntroDialog::on_browseBootstrapButton_clicked()
{
    QString file = QFileDialog::getOpenFileName(
        this,
        tr("Select bootstrap file"),
        QString(),
        tr("Blockchain data (*.dat);;All files (*.*)"));
    if (file.isEmpty())
        return;

    bootstrapFile = file;
    ui->bootstrapFile->setText(bootstrapFile);
    ui->errorLabel->clear();
}

bool IntroDialog::installBootstrapFile(const QString &dataPath)
{
    if (!ui->bootstrapCheckBox->isChecked())
        return true;

    if (bootstrapFile.isEmpty() || !QFile::exists(bootstrapFile)) {
        ui->errorLabel->setText(tr("Please select a bootstrap file."));
        return false;
    }

    boost::filesystem::path dest = boost::filesystem::path(dataPath.toStdString()) / "bootstrap.dat";
    try {
#if BOOST_VERSION >= 104000
        boost::filesystem::copy_file(
            bootstrapFile.toStdString(),
            dest,
            boost::filesystem::copy_option::overwrite_if_exists);
#else
        boost::filesystem::copy_file(bootstrapFile.toStdString(), dest);
#endif
    } catch (const boost::filesystem::filesystem_error &) {
        ui->errorLabel->setText(tr("Could not copy the bootstrap file into the data directory."));
        return false;
    }

    return true;
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

    if (!installBootstrapFile(dataDir))
        return;

    accept();
}
