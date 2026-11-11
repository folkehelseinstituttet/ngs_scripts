"""Read Excel metadata without guessing identifier columns or worksheet selection."""

from datetime import date, datetime, time
from pathlib import Path

from merge_master_csv import INDEX, SEQUENCE_COLUMNS, MergeError


IDENTIFIERS = {name.casefold() for name in (INDEX, *SEQUENCE_COLUMNS, "RekvNr", "Key", "OriginalName")}


def select_sheet(names, requested):
    if requested:
        if requested not in names:
            raise MergeError("Configured metadata worksheet does not exist")
        return requested
    if len(names) != 1:
        raise MergeError("Metadata workbook must have one worksheet; set AVIANSEQ_METADATA_SHEET to select one")
    return names[0]


def text_cell(value):
    if value is None:
        return ""
    if isinstance(value, (datetime, date, time)):
        return value.isoformat()
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def metadata_table(values):
    # Ignore completely empty trailing columns created by spreadsheet formatting.
    width = max((i + 1 for row in values for i, cell in enumerate(row)
                 if cell is not None and str(cell).strip()), default=0)
    if not width:
        raise MergeError("Metadata workbook is empty")
    header = [text_cell(value).strip() for value in values[0][:width]]
    if len(header) != width or any(not name for name in header):
        raise MergeError("Metadata worksheet requires column names in the first row")
    if len({name.casefold() for name in header}) != len(header):
        raise MergeError("Metadata worksheet has duplicate column names")
    rows = []
    for number, values_row in enumerate(values[1:], 2):
        row = list(values_row[:width])
        row.extend([None] * (width - len(row)))
        if not any(value is not None and str(value).strip() for value in row):
            continue
        for name, value in zip(header, row):
            if name.casefold() in IDENTIFIERS and value is not None and not isinstance(value, str):
                raise MergeError(f"Metadata identifier {name} at row {number} must be stored as Excel text; "
                                 "numeric cells may have lost leading zeros")
        rows.append(dict(zip(header, map(text_cell, row))))
    return header, rows


def read_excel_metadata(path, sheet=None):
    path = Path(path)
    try:
        if path.suffix.lower() == ".xls":
            try:
                import xlrd
            except ImportError as error:
                raise MergeError("Reading .xls metadata requires xlrd; install master_csv/requirements-excel.txt") from error
            book = xlrd.open_workbook(str(path), on_demand=True)
            try:
                worksheet = book.sheet_by_name(select_sheet(book.sheet_names(), sheet))
                values = []
                for row in worksheet.get_rows():
                    converted = []
                    for cell in row:
                        if cell.ctype == xlrd.XL_CELL_ERROR:
                            raise MergeError("Metadata worksheet contains an Excel error cell")
                        value = cell.value
                        if cell.ctype == xlrd.XL_CELL_DATE:
                            value = xlrd.xldate_as_datetime(value, book.datemode)
                        converted.append(value)
                    values.append(converted)
            finally:
                book.release_resources()
        elif path.suffix.lower() == ".xlsx":
            try:
                import openpyxl
            except ImportError as error:
                raise MergeError("Reading .xlsx metadata requires openpyxl; install master_csv/requirements-excel.txt") from error
            book = openpyxl.load_workbook(path, read_only=True, data_only=False)
            try:
                worksheet = book[select_sheet(book.sheetnames, sheet)]
                values = []
                for row in worksheet.iter_rows():
                    if any(cell.data_type in {"f", "e"} for cell in row):
                        raise MergeError("Metadata worksheet contains formulas or Excel errors; export values only")
                    values.append([cell.value for cell in row])
            finally:
                book.close()
        else:
            raise MergeError("Expected .xls or .xlsx metadata")
        return metadata_table(values)
    except MergeError:
        raise
    except Exception as error:
        # Avoid leaking metadata cell contents from third-party parser exceptions.
        raise MergeError(f"Cannot read metadata workbook {path.name} ({type(error).__name__})") from error
