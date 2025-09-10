require 'csv'
require 'roo'

class FileRowCountService
  def initialize(file_path)
    @file_path = file_path
  end

  def count
    case File.extname(@file_path).downcase
    when '.csv'
      count_csv_rows
    when '.xls', '.xlsx'
      count_excel_rows
    else
      0
    end
  rescue => e
    Rails.logger.error "Error counting rows: #{e.message}"
    0
  end

  private

  def count_csv_rows
    count = 0
    CSV.foreach(@file_path, headers: true) do |row|
      count += 1 if row.to_h.values.any?(&:present?)
    end
    count
  end

  def count_excel_rows
    spreadsheet = Roo::Spreadsheet.open(@file_path)
    sheet = spreadsheet.sheet(0)
    headers = sheet.row(1)

    data_row_count = 0
    row_num = 2
    consecutive_empty_rows = 0
    max_consecutive_empty = 5

    while consecutive_empty_rows < max_consecutive_empty
      has_data = false

      (1..headers.count).each do |col_index|
        cell_value = sheet.cell(row_num, col_index)
        if cell_value.present? && cell_value.to_s.strip.present?
          has_data = true
          break
        end
      end

      if has_data
        data_row_count += 1
        consecutive_empty_rows = 0
      else
        consecutive_empty_rows += 1
      end

      row_num += 1
      break if row_num > 10000
    end

    Rails.logger.info "Excel file row count: #{data_row_count} actual data rows found"
    data_row_count
  end
end