# src/orm/logger.nim
# Professional logging system for ORM Baraba

import strutils
import times
import osproc

type
  LogLevel* = enum
    Debug = "DEBUG"
    Info = "INFO"
    Warn = "WARN"
    Error = "ERROR"
    Success = "SUCCESS"

  Logger* = object
    level*: LogLevel
    verbose*: bool
    colors*: bool

var defaultLogger* = Logger(level: Info, verbose: false, colors: true)

# Color codes
const 
  ColorReset* = "\e[0m"
  ColorRed* = "\e[31m"
  ColorGreen* = "\e[32m"
  ColorYellow* = "\e[33m"
  ColorBlue* = "\e[34m"
  ColorMagenta* = "\e[35m"
  ColorCyan* = "\e[36m"
  ColorWhite* = "\e[37m"
  ColorGray* = "\e[90m"

proc isTerminal*(): bool =
  ## Simple terminal detection
  when defined(windows):
    return false
  else:
    try:
      let (output, exitCode) = execCmdEx("test -t 1")
      return exitCode == 0
    except:
      return false

proc getColorForLevel*(level: LogLevel): string =
  if not defaultLogger.colors or not isTerminal():
    return ""
  
  case level:
  of Debug: return ColorGray
  of Info: return ColorBlue
  of Warn: return ColorYellow
  of Error: return ColorRed
  of Success: return ColorGreen

proc formatMessage*(level: LogLevel, message: string): string =
  let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  let color = getColorForLevel(level)
  let colorReset = if defaultLogger.colors and isTerminal(): ColorReset else: ""
  
  return "$1[$2] [$3]$4 $5" % [color, timestamp, $level, colorReset, message]

proc log*(level: LogLevel, message: string) =
  if defaultLogger.verbose or level >= defaultLogger.level:
    echo formatMessage(level, message)

proc debug*(message: string) = 
  log(Debug, message)

proc info*(message: string) = 
  log(Info, message)

proc warn*(message: string) = 
  log(Warn, message)

proc error*(message: string) = 
  log(Error, message)

proc success*(message: string) = 
  log(Success, message)

proc setLevel*(level: LogLevel) =
  defaultLogger.level = level

proc setVerbose*(verbose: bool) =
  defaultLogger.verbose = verbose

proc setColors*(enabled: bool) =
  defaultLogger.colors = enabled

proc printHeader*(title: string) =
  if not defaultLogger.colors or not isTerminal():
    echo "\n=== " & title & " ==="
    return
    
  echo "\n" & ColorCyan & "╔══ " & title & " ═════════════════════════════════════════════════════╗" & ColorReset
  echo ColorCyan & "║" & ColorReset & "                                                                     " & ColorCyan & "║" & ColorReset
  echo ColorCyan & "╚══════════════════════════════════════════════════════════════════════════════╝" & ColorReset

proc printSection*(title: string) =
  echo "\n" & ColorYellow & "▶ " & title & ColorReset

proc printSuccessBox*(message: string) =
  if defaultLogger.colors:
    echo ColorGreen & "✓ " & message & ColorReset
  else:
    echo "✓ " & message

proc printErrorBox*(message: string) =
  if defaultLogger.colors:
    echo ColorRed & "✗ " & message & ColorReset
  else:
    echo "✗ " & message

proc printWarningBox*(message: string) =
  if defaultLogger.colors:
    echo ColorYellow & "⚠ " & message & ColorReset
  else:
    echo "⚠ " & message

proc printInfoBox*(message: string) =
  if defaultLogger.colors:
    echo ColorBlue & "ℹ " & message & ColorReset
  else:
    echo "ℹ " & message

proc printTable*(headers: seq[string], rows: seq[seq[string]]) =
  ## Print formatted table
  if headers.len == 0: return
  
  # Calculate column widths
  var widths: seq[int]
  for i in 0..<headers.len:
    widths.add(headers[i].len)
    for row in rows:
      if i < row.len:
        widths[i] = max(widths[i], row[i].len)
  
  # Print header separator
  var separator = "+"
  for width in widths:
    separator.add("-".repeat(width + 2) & "+")
  
  echo "\n" & separator
  
  # Print headers
  var headerRow = "|"
  for i, header in headers:
    headerRow.add(" " & header.alignLeft(widths[i]) & " |")
  echo headerRow
  echo separator
  
  # Print rows
  for row in rows:
    var dataRow = "|"
    for i in 0..<headers.len:
      let cell = if i < row.len: row[i] else: ""
      dataRow.add(" " & cell.alignLeft(widths[i]) & " |")
    echo dataRow
  
  echo separator

proc progressBar*(current, total: int, label: string = "Processing") =
  ## Show progress bar
  let progress = current.float / total.float
  let barWidth = 40
  let filledWidth = int(progress * barWidth.float)
  let bar = "=".repeat(filledWidth) & " ".repeat(barWidth - filledWidth)
  let percentage = int(progress * 100)
  
  let line = "\r$1: [$2] $3% ($4/$5)" % [label, bar, $percentage, $current, $total]
  stdout.write(line)
  
  if current == total:
    echo ""