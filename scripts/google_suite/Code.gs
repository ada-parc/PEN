/**
 * PEN navigator records, Google Sheets version (demo / fallback).
 *
 * Paste into Extensions > Apps Script in the PRIVATE roster spreadsheet, then
 * run setupRoster() once. See README.md in this folder.
 *
 * Tabs:
 *   Roster     name, email, consent date, code, personal link, link sent.
 *              Holds names, so keep this spreadsheet private.
 *   Check-ins  the check-in Form's responses (Timestamp, Code, Module).
 *              Link the Form to this spreadsheet, or to a second one that the
 *              wider team may see (see README, "Keeping names apart").
 *   Dashboard  one row per navigator: who has checked in, per module.
 */

var SITE = "https://ada-parc.github.io/PEN/";
var MODULES = ["module-01", "module-02", "module-03"];
var CHECKINS_SHEET = "Check-ins"; // the tab name the Form writes to

// Damm check digit: the same table as scripts/navigator_codes.py and
// assets/navigator-init.html.
var DAMM = [
  [0, 3, 1, 7, 5, 9, 8, 6, 4, 2], [7, 0, 9, 2, 1, 5, 4, 8, 6, 3],
  [4, 2, 0, 6, 8, 7, 1, 3, 5, 9], [1, 7, 5, 0, 9, 8, 3, 4, 2, 6],
  [6, 1, 2, 3, 0, 4, 5, 9, 7, 8], [3, 6, 7, 4, 2, 0, 9, 5, 8, 1],
  [5, 8, 6, 9, 7, 2, 0, 1, 3, 4], [8, 9, 4, 5, 3, 6, 2, 0, 1, 7],
  [9, 4, 3, 8, 6, 1, 7, 2, 0, 5], [2, 5, 8, 1, 4, 3, 6, 7, 9, 0]
];

function codeFor_(n) {
  var digits = ("00" + n).slice(-3), interim = 0;
  for (var i = 0; i < digits.length; i++) interim = DAMM[interim][+digits[i]];
  return "N-" + digits + "-" + interim;
}

/** Roster tab with codes N-000-0 (the test code) through N-<count>. */
function setupRoster(count) {
  count = count || 10;
  var ss = SpreadsheetApp.getActive();
  var sh = ss.getSheetByName("Roster") || ss.insertSheet("Roster");
  sh.clear();
  sh.appendRow(["Code", "Name", "Email", "Consent date", "Personal link", "Link sent"]);
  var rows = [];
  for (var n = 0; n <= count; n++) {
    var code = codeFor_(n);
    rows.push([code, n === 0 ? "TEST (never give out)" : "", "", "", SITE + "?nav=" + code, ""]);
  }
  sh.getRange(2, 1, rows.length, 6).setValues(rows);
  sh.setFrozenRows(1);
  sh.getRange("A:A").setFontFamily("Roboto Mono");
  sh.autoResizeColumns(1, 6);
  setupDashboard();
}

/** Dashboard tab: formulas only, so it updates as responses arrive. */
function setupDashboard() {
  var ss = SpreadsheetApp.getActive();
  var sh = ss.getSheetByName("Dashboard") || ss.insertSheet("Dashboard");
  sh.clear();
  var head = ["Code", "Name"].concat(MODULES, ["Checked in", "Certificate earned"]);
  sh.appendRow(head);
  var last = ss.getSheetByName("Roster").getLastRow();
  for (var r = 2; r <= last; r++) {
    var row = [
      "=Roster!A" + r,
      "=Roster!B" + r
    ];
    MODULES.forEach(function (m, i) {
      var col = String.fromCharCode(67 + i); // C, D, E
      row.push('=IF(COUNTIFS(\'' + CHECKINS_SHEET + '\'!B:B,$A' + r + ",'" + CHECKINS_SHEET + "'!C:C,\"" + m + "\")>0,\"✓\",\"\")");
    });
    row.push('=COUNTIF(C' + r + ':E' + r + ',"✓")');
    row.push('=IF(F' + r + '=' + MODULES.length + ',"Yes","")');
    sh.appendRow(row);
  }
  // Check-ins whose code is not on the Roster (typo, edited link).
  var unk = last + 2;
  sh.getRange(unk, 1).setValue("Check-ins with a code not on the Roster:");
  sh.getRange(unk, 3).setFormula(
    "=COUNTA('" + CHECKINS_SHEET + "'!B2:B)-SUMPRODUCT(COUNTIF(Roster!A2:A,'" + CHECKINS_SHEET + "'!B2:B))"
  );
  sh.setFrozenRows(1);
  sh.autoResizeColumns(1, head.length);
}

/**
 * Emails each Roster row that has an email and no "Link sent" date.
 * Run it only for real navigators; it sends real email.
 */
function sendLinks() {
  var sh = SpreadsheetApp.getActive().getSheetByName("Roster");
  var data = sh.getDataRange().getValues();
  for (var i = 1; i < data.length; i++) {
    var code = data[i][0], name = data[i][1], email = data[i][2], link = data[i][4], sent = data[i][5];
    if (!email || sent || code === codeFor_(0)) continue;
    MailApp.sendEmail(email, "Your PEN training link",
      "Hello " + (name || "") + ",\n\nHere is your personal link to the PEN training:\n" + link +
      "\n\nOpen it once on the device you will use. It carries your navigator code, " + code +
      ", and nothing else.\n\nThe PEN team");
    sh.getRange(i + 1, 6).setValue(new Date());
  }
}
