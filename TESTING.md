# Testing

### In order to test Pop!_Shop, you must do the following:

```
killall io.elementary.appcenter
sudo apt install pop-shop
io.elementary.appcenter
```

#### Check the following:

 - [ ] Search works on the main page and inside a category
 - [ ] Search bar is useable without requiring explicit focus on both the Home and any Catagory page
 - [ ] Installing a new application and uninstalling it works
 - [ ] Viewing installed applications from the Updates menu works
 - [ ] Right clicking on applications in GNOME Shell and clicking on "Show Details" works for programs with appstream data
 - [ ] Pop!_Picks display in a random order
 - [ ] Swipe gesture goes back from an app listing or category
 - [ ] `Ctrl`+`R` Refreshes Apt Cache and Flatpak Metadata
 - [ ] `Crtl`+`S` Opens Software Sources (repoman)
