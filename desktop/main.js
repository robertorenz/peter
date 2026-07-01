const { app, BrowserWindow, Menu } = require("electron");

app.whenReady().then(() => {
  Menu.setApplicationMenu(null);
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    backgroundColor: "#15212a",
    autoHideMenuBar: true,
    show: false,
  });
  win.once("ready-to-show", () => { win.maximize(); win.show(); });
  win.loadFile("index.html");
});

app.on("window-all-closed", () => app.quit());
