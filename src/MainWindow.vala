/* Copyright 2015 Marvin Beckers <beckersmarvin@gmail.com>
*
* This program is free software: you can redistribute it
* and/or modify it under the terms of the GNU General Public License as
* published by the Free Software Foundation, either version 3 of the
* License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be
* useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
* Public License for more details.
*
* You should have received a copy of the GNU General Public License along
* with this program. If not, see http://www.gnu.org/licenses/.
*/

public class AppCenter.MainWindow : Hdy.ApplicationWindow {
    public bool working { get; set; }

    private AppCenter.SearchView search_view;
    private Gtk.Revealer view_mode_revealer;
    private Gtk.SearchEntry search_entry;
    private Gtk.ModelButton refresh_menuitem;
    private Gtk.Button return_button;
    private Gtk.Label updates_badge;
    private Gtk.Revealer updates_badge_revealer;
    private Granite.Widgets.Toast toast;
    private Granite.Widgets.OverlayBar overlaybar;
    private Hdy.Deck deck;
#if POP_OS
    private Gtk.ModelButton installed_menuitem;
    private Gtk.Label updates_menubadge;
    private Gtk.Stack updates_menubadge_stack;
#endif

    private AppCenterCore.Package? last_installed_package;

    private uint configure_id;

    private bool mimetype;

    private const int VALID_QUERY_LENGTH = 3;

    public static Views.AppListUpdateView installed_view { get; private set; }

    public MainWindow (Gtk.Application app) {
        Object (application: app);

        search_entry.grab_focus_without_selecting ();

        var go_back = new SimpleAction ("go-back", null);
        go_back.activate.connect (() => deck.navigate (Hdy.NavigationDirection.BACK));
        add_action (go_back);

        var focus_search = new SimpleAction ("focus-search", null);
        focus_search.activate.connect (() => search_entry.grab_focus ());
        add_action (focus_search);

        app.set_accels_for_action ("win.go-back", {"<Alt>Left", "Back"});
        app.set_accels_for_action ("win.focus-search", {"<Ctrl>f"});

        button_release_event.connect ((event) => {
            // On back mouse button pressed
            if (event.button == 8) {
                deck.navigate (Hdy.NavigationDirection.BACK);
                return true;
            }

            return false;
        });

        search_entry.search_changed.connect (() => trigger_search ());

        search_entry.key_press_event.connect ((event) => {
            if (event.keyval == Gdk.Key.Escape) {
                search_entry.text = "";
                return true;
            }

            if (event.keyval == Gdk.Key.Down) {
                search_entry.move_focus (Gtk.DirectionType.TAB_FORWARD);
                return true;
            }

            return false;
        });

        unowned var aggregator = AppCenterCore.BackendAggregator.get_default ();
        aggregator.bind_property ("working", this, "working", GLib.BindingFlags.SYNC_CREATE);
        aggregator.bind_property ("working", overlaybar, "active", GLib.BindingFlags.SYNC_CREATE);

        aggregator.notify ["job-type"].connect (() => {
            update_overlaybar_label (aggregator.job_type);
        });

        notify["working"].connect (() => {
            Idle.add (() => {
                App.refresh_action.set_enabled (!working);
                App.repair_action.set_enabled (!working);
                return GLib.Source.REMOVE;
            });
        });

        update_overlaybar_label (aggregator.job_type);
    }

    construct {
        icon_name = Build.PROJECT_NAME;
        set_default_size (910, 640);
        height_request = 500;

        title = _(Build.APP_NAME);

        toast = new Granite.Widgets.Toast ("");

        toast.default_action.connect (() => {
            if (last_installed_package != null) {
                try {
                    last_installed_package.launch ();
                } catch (Error e) {
                    warning ("Failed to launch %s: %s".printf (last_installed_package.get_name (), e.message));

                    var message_dialog = new Granite.MessageDialog.with_image_from_icon_name (
                        _("Failed to launch “%s“").printf (last_installed_package.get_name ()),
                        e.message,
                        "system-software-install",
                        Gtk.ButtonsType.CLOSE
                    );
                    message_dialog.badge_icon = new ThemedIcon ("dialog-error");
                    message_dialog.transient_for = this;

                    message_dialog.present ();
                    message_dialog.response.connect ((response_id) => {
                        message_dialog.destroy ();
                    });
                }
            }
        });

        return_button = new Gtk.Button () {
            action_name = "win.go-back",
            no_show_all = true,
            valign = Gtk.Align.CENTER
        };
        return_button.get_style_context ().add_class (Granite.STYLE_CLASS_BACK_BUTTON);

        var updates_button = new Gtk.Button.from_icon_name ("software-update-available", Gtk.IconSize.LARGE_TOOLBAR);

        var badge_provider = new Gtk.CssProvider ();
        badge_provider.load_from_resource ("io/elementary/appcenter/badge.css");

        updates_badge = new Gtk.Label ("!");

        unowned var badge_context = updates_badge.get_style_context ();
        badge_context.add_class (Granite.STYLE_CLASS_BADGE);
        badge_context.add_provider (badge_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        updates_badge_revealer = new Gtk.Revealer () {
            halign = Gtk.Align.END,
            valign = Gtk.Align.START,
            transition_type = Gtk.RevealerTransitionType.CROSSFADE
        };
        updates_badge_revealer.add (updates_badge);

        var eventbox_badge = new Gtk.EventBox () {
            halign = Gtk.Align.END
        };
        eventbox_badge.add (updates_badge_revealer);
        
#if POP_OS
        updates_menubadge_stack = new Gtk.Stack () {
            halign = Gtk.Align.END,
            transition_type = Gtk.StackTransitionType.CROSSFADE
        };

        var installed_shortcut = new Gtk.Grid () {
            halign = Gtk.Align.END
        };
        var ctrl_key = new Gtk.Label ("Ctrl");
        var i_key = new Gtk.Label ("I");
        installed_shortcut.attach (ctrl_key, 0, 0);
        installed_shortcut.attach (i_key, 1, 0);

        unowned var ctrl_context = ctrl_key.get_style_context ();
        ctrl_context.add_class ("keycap");
        unowned var i_context = i_key.get_style_context ();
        i_context.add_class ("keycap");
        updates_menubadge_stack.add_named (installed_shortcut, "shortcut");

        updates_menubadge = new Gtk.Label ("!") {
            halign = Gtk.Align.END
        };
        unowned var menubadge_context = updates_menubadge.get_style_context ();
        menubadge_context.add_class (Granite.STYLE_CLASS_BADGE);
        menubadge_context.add_class ("menubadge");
        menubadge_context.add_provider (badge_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        updates_menubadge_stack.add_named (updates_menubadge, "updates");
#else
        var updates_overlay = new Gtk.Overlay () {
            tooltip_text = C_("view", "Updates & installed apps")
        };
        updates_overlay.add (updates_button);
        updates_overlay.add_overlay (eventbox_badge);

        view_mode_revealer = new Gtk.Revealer () {
            reveal_child = true,
            transition_type = Gtk.RevealerTransitionType.SLIDE_LEFT
        };
        view_mode_revealer.add (updates_overlay);
#endif

        search_entry = new Gtk.SearchEntry () {
            hexpand = true,
            placeholder_text = _("Search Apps"),
            valign = Gtk.Align.CENTER
        };

        var search_clamp = new Hdy.Clamp ();
        search_clamp.add (search_entry);

        var automatic_updates_button = new Granite.SwitchModelButton (_("Automatic App Updates")) {
            description = _("System updates and unpaid apps will not update automatically")
        };

        var refresh_accellabel = new Granite.AccelLabel.from_action_name (
#if POP_OS
            _("Refresh"),
#else
            _("Check for Updates"),
#endif
            "app.refresh"
        );

        refresh_menuitem = new Gtk.ModelButton () {
            action_name = "app.refresh"
        };
        refresh_menuitem.get_child ().destroy ();
        refresh_menuitem.add (refresh_accellabel);

        var menu_popover_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
            margin_bottom = 6,
            margin_top = 6
        };
#if POP_OS
        var installed_accellabel = new Granite.AccelLabel.from_action_name (
            _("Updates & Installed Software"),
            "app.show-updates"
        );
        installed_menuitem = new Gtk.ModelButton () {
            action_name = "app.show-updates"
        };
        installed_menuitem.get_child ().destroy ();
        var installed_menubox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        installed_menuitem.add (installed_menubox);
        var installed_label = new Gtk.Label (_("Updates & Installed Software"));
        installed_label.halign = Gtk.Align.START;
        installed_label.hexpand = true;
        installed_menubox.add (installed_label);
        menu_popover_box.add (installed_menuitem);

        installed_menubox.add (updates_menubadge_stack);

        var menu_separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        menu_popover_box.add (menu_separator);
        
        var auto_accellabel = new Granite.AccelLabel.from_action_name (
            _("Automatic Updates…"),
            "app.auto"
        );
        var auto_menuitem = new Gtk.ModelButton () {
            action_name = "app.auto"
        };
        auto_menuitem.get_child ().destroy ();
        auto_menuitem.add (auto_accellabel);

        var repos_accellabel = new Granite.AccelLabel.from_action_name (
            _("System Software Sources…"),
            "app.repos"
        );
        var repos_menuitem = new Gtk.ModelButton () {
            action_name = "app.repos"
        };
        repos_menuitem.get_child ().destroy ();
        repos_menuitem.add (repos_accellabel);
        
        menu_popover_box.add (auto_menuitem);
        menu_popover_box.add (repos_menuitem);
        menu_popover_box.add (refresh_menuitem);
#else
        menu_popover_box.add (automatic_updates_button);
        menu_popover_box.add (refresh_menuitem);
#endif
        menu_popover_box.show_all ();

        var menu_popover = new Gtk.Popover (null);
        menu_popover.add (menu_popover_box);

        var menu_button = new Gtk.MenuButton () {
            image = new Gtk.Image.from_icon_name ("open-menu", Gtk.IconSize.LARGE_TOOLBAR),
            popover = menu_popover,
            tooltip_text = _("Settings"),
            valign = Gtk.Align.CENTER
        };

        var headerbar = new Hdy.HeaderBar () {
            show_close_button = true
        };
        headerbar.set_custom_title (search_clamp);
        headerbar.pack_start (return_button);
#if POP_OS
        var updates_overlay = new Gtk.Overlay () {};
        updates_overlay.add (menu_button);
        updates_overlay.add_overlay (eventbox_badge);
        headerbar.pack_end (updates_overlay);
#else
        headerbar.pack_end (menu_button);
        headerbar.pack_end (view_mode_revealer);
#endif

        var homepage = new Homepage ();
        installed_view = new Views.AppListUpdateView ();

        deck = new Hdy.Deck () {
            can_swipe_back = true
        };
        deck.add (homepage);

        var overlay = new Gtk.Overlay ();
        overlay.add_overlay (toast);
        overlay.add (deck);

        overlaybar = new Granite.Widgets.OverlayBar (overlay);
        overlaybar.bind_property ("active", overlaybar, "visible");

        var network_info_bar_label = new Gtk.Label ("<b>%s</b> %s".printf (
            _("Network Not Available."),
            _("Connect to the Internet to browse and install apps.")
        )) {
            use_markup = true,
            wrap = true
        };

        var network_info_bar = new Gtk.InfoBar () {
            message_type = Gtk.MessageType.WARNING
        };
        network_info_bar.get_content_area ().add (network_info_bar_label);
        network_info_bar.add_button (_("Network Settings…"), Gtk.ResponseType.ACCEPT);
        
        network_info_bar.response.connect ((response_id) => {
            switch (response_id) {
                case Gtk.ResponseType.ACCEPT:
                    try {
                        open_network_settings ();
                    } catch (GLib.Error e) {
                        critical (e.message);
                    }
                    break;
                default:
                    assert_not_reached ();
            }
        });

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        box.add (headerbar);
        box.add (network_info_bar);

        if (Utils.is_running_in_demo_mode ()) {
            var demo_mode_info_bar_label = new Gtk.Label ("<b>%s</b> %s".printf (
                _("Running in Demo Mode"),
                _("Install %s to browse and install apps.").printf (Environment.get_os_info (GLib.OsInfoKey.NAME))
            )) {
                use_markup = true,
                wrap = true
            };

            var demo_mode_info_bar = new Gtk.InfoBar () {
                message_type = Gtk.MessageType.WARNING
            };
            demo_mode_info_bar.get_content_area ().add (demo_mode_info_bar_label);

            box.add (demo_mode_info_bar);
        }

        box.add (overlay);
        box.show_all ();

        add (box);

        int window_width, window_height;
        App.settings.get ("window-size", "(ii)", out window_width, out window_height);
        App.settings.bind (
            "automatic-updates",
            automatic_updates_button,
            "active",
            SettingsBindFlags.DEFAULT
        );

        resize (window_width, window_height);

        if (App.settings.get_boolean ("window-maximized")) {
            maximize ();
        }

        var client = AppCenterCore.Client.get_default ();

        automatic_updates_button.notify["active"].connect (() => {
            if (automatic_updates_button.active) {
                client.update_cache.begin (true, AppCenterCore.Client.CacheUpdateType.FLATPAK);
            } else {
                client.cancel_updates (true);
            }
        });

        client.notify["updates-number"].connect (() => {
            show_update_badge (client.updates_number);
        });

        var network_monitor = NetworkMonitor.get_default ();
        network_monitor.bind_property ("network-available", network_info_bar, "revealed", BindingFlags.INVERT_BOOLEAN | BindingFlags.SYNC_CREATE);

        network_info_bar.response.connect (() => {
            try {
                Gtk.show_uri_on_window (this, "settings://network", Gdk.CURRENT_TIME);
            } catch (GLib.Error e) {
                critical (e.message);
            }
        });

        updates_button.clicked.connect (() => {
            go_to_installed ();
        });

        eventbox_badge.button_release_event.connect (() => {
#if POP_OS
            menu_button.active = !menu_button.active;
#else
            go_to_installed ();
#endif
        });

        homepage.show_category.connect ((category) => {
            show_category (category);
        });

        homepage.show_package.connect ((package) => {
            show_package (package);
        });

        installed_view.show_app.connect ((package) => {
            show_package (package);
        });

        destroy.connect (() => {
           installed_view.clear ();
        });

        deck.notify["visible-child"].connect (() => {
            if (!deck.transition_running) {
                update_navigation ();
            }
        });

        deck.notify["transition-running"].connect (() => {
            if (!deck.transition_running) {
                update_navigation ();
            }
        });
    }

    public override bool configure_event (Gdk.EventConfigure event) {
        if (configure_id == 0) {
            /* Avoid spamming the settings */
            configure_id = Timeout.add (200, () => {
                configure_id = 0;

                if (is_maximized) {
                    App.settings.set_boolean ("window-maximized", true);
                } else {
                    App.settings.set_boolean ("window-maximized", false);

                    int width, height;
                    get_size (out width, out height);
                    App.settings.set ("window-size", "(ii)", width, height);
                }

                return GLib.Source.REMOVE;
            });
        }

        return base.configure_event (event);
    }

    public override bool delete_event (Gdk.EventAny event) {
        if (working) {
            hide ();

            notify["working"].connect (() => {
                if (!visible && !working) {
                    destroy ();
                }
            });

            AppCenterCore.Client.get_default ().cancel_updates (false); //Timeouts keep running
            return true;
        }

        return false;
    }

    private void show_update_badge (uint updates_number) {
        Idle.add (() => {
            if (updates_number == 0U) {
                updates_badge_revealer.reveal_child = false;
            } else {
                updates_badge.label = updates_number.to_string ();
                updates_badge_revealer.reveal_child = true;
            }

#if POP_OS
            if (updates_number == 0U) {
                updates_menubadge_stack.set_visible_child_name ("shortcut");
            } else {
                updates_menubadge.label = updates_number.to_string ();
                updates_menubadge_stack.set_visible_child_name ("updates");
            }
#endif

            return GLib.Source.REMOVE;
        });
    }

    public void show_package (AppCenterCore.Package package, bool remember_history = true) {
        if (deck.transition_running) {
            return;
        }

        var package_hash = package.hash;

        var pk_child = deck.get_child_by_name (package_hash) as Views.AppInfoView;
        if (pk_child != null && pk_child.to_recycle) {
            // Don't switch to a view that needs recycling
            pk_child.destroy ();
            pk_child = null;
        }

        if (pk_child != null) {
            pk_child.view_entered ();
            deck.visible_child = pk_child;
            return;
        }

        var app_info_view = new Views.AppInfoView (package);
        app_info_view.show_all ();

        deck.add (app_info_view);
        deck.visible_child = app_info_view;

        app_info_view.show_other_package.connect ((_package, remember_history, transition) => {
            if (!transition) {
                deck.transition_duration = 0;
            }

            show_package (_package, remember_history);
            if (remember_history) {
                set_return_name (package.get_name ());
            }
            deck.transition_duration = 200;
        });
    }

    private void update_navigation () {
        var previous_child = deck.get_adjacent_child (Hdy.NavigationDirection.BACK);

        if (deck.visible_child is Homepage) {
            view_mode_revealer.reveal_child = true;
            configure_search (true, _("Search Apps"), "");
        } else if (deck.visible_child is CategoryView) {
            var current_category = ((CategoryView) deck.visible_child).category;
            view_mode_revealer.reveal_child = false;
            configure_search (true, _("Search %s").printf (current_category.name), "");
        } else if (deck.visible_child == search_view) {
            if (previous_child is CategoryView) {
                var previous_category = ((CategoryView) previous_child).category;
                configure_search (true, _("Search %s").printf (previous_category.name));
                view_mode_revealer.reveal_child = false;
            } else {
                configure_search (true);
                view_mode_revealer.reveal_child = true;
            }
        } else if (deck.visible_child is Views.AppInfoView) {
            view_mode_revealer.reveal_child = false;
            configure_search (false);
        } else if (deck.visible_child is Views.AppListUpdateView) {
            view_mode_revealer.reveal_child = true;
            configure_search (false);
        }

        if (previous_child == null) {
            set_return_name (null);
        } else if (previous_child is Homepage) {
            set_return_name (_("Home"));
        } else if (previous_child == search_view) {
            /// TRANSLATORS: the name of the Search view
            set_return_name (C_("view", "Search"));
        } else if (previous_child is Views.AppInfoView) {
            set_return_name (((Views.AppInfoView) previous_child).package.get_name ());
        } else if (previous_child is CategoryView) {
            set_return_name (((CategoryView) previous_child).category.name);
        } else if (previous_child is Views.AppListUpdateView) {
            set_return_name (C_("view", "Installed"));
        }

        while (deck.get_adjacent_child (Hdy.NavigationDirection.FORWARD) != null) {
            var next_child = deck.get_adjacent_child (Hdy.NavigationDirection.FORWARD);
            if (next_child is AppCenter.Views.AppListUpdateView) {
                deck.remove (next_child);
            } else {
                next_child.destroy ();
            }
        }
    }

    public void go_to_installed () {
        if (deck.get_children ().find (installed_view) == null) {
            deck.add (installed_view);
        }
        installed_view.show_all ();
        deck.visible_child = installed_view;
    }
    
    public void open_network_settings () {
        AppInfo settings = AppInfo.create_from_commandline ("gnome-control-center network", "Settings", NONE);
        settings.launch (null, null);
    }

    public void search (string term, bool mimetype = false) {
        this.mimetype = mimetype;
        search_entry.text = term;
    }

    public void send_installed_toast (AppCenterCore.Package package) {
        last_installed_package = package;

        // Only show a toast when we're not on the installed app's page
        if (deck.visible_child is Views.AppInfoView && ((Views.AppInfoView) deck.visible_child).package == package) {
            return;
        }

        toast.title = _("“%s” has been installed").printf (package.get_name ());
        // Show Open only when a desktop app is installed
        if (package.component.get_kind () == AppStream.ComponentKind.DESKTOP_APP) {
            toast.set_default_action (_("Open"));
        } else {
            toast.set_default_action (null);
        }

        toast.send_notification ();
    }

    private void trigger_search () {
        unowned string search_term = search_entry.text;
        uint query_length = search_term.length;
        bool query_valid = query_length >= VALID_QUERY_LENGTH;

        view_mode_revealer.reveal_child = !query_valid;

        if (query_valid) {
            if (deck.visible_child != search_view) {
                search_view = new AppCenter.SearchView ();
                search_view.show_all ();

                search_view.show_app.connect ((package) => {
                    show_package (package);
                });

                deck.add (search_view);
                deck.visible_child = search_view;
            }

            search_view.clear ();
            search_view.current_search_term = search_term;

            unowned var client = AppCenterCore.Client.get_default ();

            Gee.Collection<AppCenterCore.Package> found_apps;

            if (mimetype) {
                found_apps = client.search_applications_mime (search_term);
                search_view.add_packages (found_apps);
            } else {
                AppStream.Category current_category = null;

                var previous_child = deck.get_adjacent_child (Hdy.NavigationDirection.BACK);
                if (previous_child is CategoryView) {
                    current_category = ((CategoryView) previous_child).category;
                }

                found_apps = client.search_applications (search_term, current_category);
                search_view.add_packages (found_apps);
            }

        } else {
            // Prevent navigating away from category views when backspacing
            if (deck.visible_child == search_view) {
                deck.navigate (Hdy.NavigationDirection.BACK);
            }
        }

        if (mimetype) {
            mimetype = false;
        }
    }

    private void set_return_name (string? return_name) {
        if (return_name != null) {
            return_button.label = return_name;
        }

        return_button.no_show_all = return_name == null;
        return_button.visible = return_name != null;
    }

    private void configure_search (bool sensitive, string? placeholder_text = _("Search Apps"), string? search_term = null) {
        search_entry.sensitive = sensitive;
        search_entry.placeholder_text = placeholder_text;

        if (search_term != null) {
            search_entry.text = "";
        }

        if (sensitive) {
            search_entry.grab_focus_without_selecting ();
        }
    }

    private void show_category (AppStream.Category category) {
        var child = deck.get_child_by_name (category.name);
        if (child != null) {
            deck.visible_child = child;
            return;
        }

        var category_view = new CategoryView (category);

        deck.add (category_view);
        deck.visible_child = category_view;

        category_view.show_app.connect ((package) => {
            show_package (package);
            set_return_name (category.name);
        });
    }

    private void update_overlaybar_label (AppCenterCore.Job.Type job_type) {
        switch (job_type) {
            case GET_DETAILS_FOR_PACKAGE_IDS:
            case GET_PACKAGE_DEPENDENCIES:
            case GET_PACKAGE_DETAILS:
            case IS_PACKAGE_INSTALLED:
                overlaybar.label = _("Getting app information…");
                break;
            case GET_DOWNLOAD_SIZE:
                overlaybar.label = _("Getting download size…");
                break;
            case GET_PREPARED_PACKAGES:
            case GET_INSTALLED_PACKAGES:
            case GET_UPDATES:
            case REFRESH_CACHE:
                overlaybar.label = _("Checking for updates…");
                break;
            case INSTALL_PACKAGE:
                overlaybar.label = _("Installing…");
                break;
            case UPDATE_PACKAGE:
                overlaybar.label = _("Installing updates…");
                break;
            case REMOVE_PACKAGE:
                overlaybar.label = _("Uninstalling…");
                break;
            case REPAIR:
                overlaybar.label = _("Repairing…");
                break;
        }
    }
}
