import Foundation

/// HTML templates for the Web UI
enum HTMLTemplates {
    /// Main admin page HTML
    static let adminPage = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>SwiftStore Admin</title>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                background-color: #f5f5f5;
                color: #333;
            }

            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 0 24px;
                font-size: 20px;
                font-weight: 600;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                display: flex;
                align-items: center;
                gap: 24px;
                height: 56px;
            }

            .header-title {
                font-size: 20px;
                font-weight: 600;
            }

            .header-nav {
                display: flex;
                gap: 8px;
            }

            .header-nav a {
                color: rgba(255, 255, 255, 0.7);
                text-decoration: none;
                padding: 8px 16px;
                border-radius: 6px;
                font-size: 14px;
                font-weight: 500;
                transition: all 0.2s;
            }

            .header-nav a:hover {
                background: rgba(255, 255, 255, 0.1);
                color: white;
            }

            .header-nav a.active {
                background: rgba(255, 255, 255, 0.2);
                color: white;
            }

            .container {
                display: flex;
                height: calc(100vh - 56px);
            }

            .sidebar {
                width: 220px;
                background: white;
                border-right: 1px solid #e0e0e0;
                overflow-y: auto;
                flex-shrink: 0;
            }

            .sidebar-title {
                padding: 16px;
                font-weight: 600;
                color: #666;
                font-size: 12px;
                text-transform: uppercase;
                letter-spacing: 0.5px;
                border-bottom: 1px solid #e0e0e0;
            }

            .table-list {
                list-style: none;
            }

            .table-item {
                padding: 12px 16px;
                cursor: pointer;
                border-bottom: 1px solid #f0f0f0;
                transition: background-color 0.2s;
                display: flex;
                align-items: center;
                gap: 8px;
            }

            .table-item:hover {
                background-color: #f5f5f5;
            }

            .table-item.active {
                background-color: #e8f0fe;
                color: #1a73e8;
                font-weight: 500;
            }

            .table-icon {
                width: 16px;
                height: 16px;
                opacity: 0.6;
            }

            .main-content {
                flex: 1;
                padding: 20px;
                overflow-y: auto;
                display: flex;
                flex-direction: column;
                gap: 20px;
            }

            .query-section {
                background: white;
                border-radius: 8px;
                padding: 16px;
                box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            }

            .query-label {
                font-weight: 500;
                margin-bottom: 8px;
                color: #555;
            }

            .query-input {
                width: 100%;
                min-height: 80px;
                padding: 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
                font-size: 13px;
                resize: vertical;
                margin-bottom: 12px;
            }

            .query-input:focus {
                outline: none;
                border-color: #667eea;
                box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
            }

            .btn {
                padding: 10px 20px;
                border: none;
                border-radius: 6px;
                cursor: pointer;
                font-weight: 500;
                font-size: 14px;
                transition: all 0.2s;
            }

            .btn-primary {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }

            .btn-primary:hover {
                transform: translateY(-1px);
                box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
            }

            .btn-secondary {
                background: #f0f0f0;
                color: #333;
                margin-left: 8px;
            }

            .btn-secondary:hover {
                background: #e0e0e0;
            }

            .data-section {
                background: white;
                border-radius: 8px;
                box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                flex: 1;
                display: flex;
                flex-direction: column;
                min-height: 0;
            }

            .data-header {
                padding: 16px;
                border-bottom: 1px solid #e0e0e0;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }

            .data-title {
                font-weight: 600;
                font-size: 16px;
            }

            .data-info {
                color: #666;
                font-size: 13px;
            }

            .table-container {
                flex: 1;
                overflow: auto;
            }

            table {
                width: 100%;
                border-collapse: collapse;
                font-size: 13px;
            }

            th {
                background: #f8f9fa;
                padding: 12px 16px;
                text-align: left;
                font-weight: 600;
                color: #555;
                border-bottom: 2px solid #e0e0e0;
                position: sticky;
                top: 0;
                white-space: nowrap;
            }

            .column-type-hint {
                font-weight: 400;
                font-size: 11px;
                color: #888;
                margin-top: 2px;
                font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            }

            td {
                padding: 10px 16px;
                border-bottom: 1px solid #f0f0f0;
                max-width: 400px;
                overflow: hidden;
                text-overflow: ellipsis;
                white-space: nowrap;
                cursor: pointer;
            }

            td:hover {
                background-color: #e8f0fe;
            }

            /* Modal styles */
            .modal-overlay {
                display: none;
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                z-index: 1000;
                justify-content: center;
                align-items: center;
            }

            .modal-overlay.visible {
                display: flex;
            }

            .modal {
                background: white;
                border-radius: 8px;
                box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
                width: 90%;
                height: 90%;
                max-width: 1200px;
                max-height: 90%;
                display: flex;
                flex-direction: column;
            }

            .modal-header {
                padding: 16px;
                border-bottom: 1px solid #e0e0e0;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }

            .modal-title {
                font-weight: 600;
                font-size: 16px;
            }

            .modal-actions {
                display: flex;
                gap: 8px;
                align-items: center;
            }

            .modal-close {
                background: none;
                border: none;
                font-size: 24px;
                cursor: pointer;
                color: #666;
                padding: 0 8px;
            }

            .modal-close:hover {
                color: #333;
            }

            .btn-copy {
                padding: 6px 12px;
                border: 1px solid #ddd;
                background: white;
                border-radius: 4px;
                cursor: pointer;
                font-size: 13px;
                transition: all 0.2s;
            }

            .btn-copy:hover {
                background: #f5f5f5;
                border-color: #ccc;
            }

            .btn-copy.copied {
                background: #e8f5e9;
                border-color: #4caf50;
                color: #2e7d32;
            }

            .modal-body {
                padding: 16px;
                overflow: auto;
                flex: 1;
            }

            .modal-content {
                font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
                font-size: 13px;
                white-space: pre-wrap;
                word-break: break-all;
                background: #f8f9fa;
                padding: 16px;
                border-radius: 6px;
                height: 100%;
                overflow: auto;
            }

            .format-toggle {
                display: flex;
                align-items: center;
                gap: 8px;
                font-size: 13px;
                color: #666;
            }

            .format-toggle input {
                cursor: pointer;
            }

            .json-key {
                color: #881391;
            }

            .json-string {
                color: #1a1aa6;
            }

            .json-number {
                color: #1c00cf;
            }

            .json-boolean {
                color: #0d22aa;
            }

            .json-null {
                color: #808080;
            }

            tr:hover {
                background-color: #f8f9fa;
            }

            .null-value {
                color: #999;
                font-style: italic;
            }

            .pagination {
                padding: 16px;
                border-top: 1px solid #e0e0e0;
                display: flex;
                justify-content: center;
                align-items: center;
                gap: 16px;
            }

            .pagination button {
                padding: 8px 16px;
                border: 1px solid #ddd;
                background: white;
                border-radius: 4px;
                cursor: pointer;
                transition: all 0.2s;
            }

            .pagination button:hover:not(:disabled) {
                background: #f5f5f5;
                border-color: #ccc;
            }

            .pagination button:disabled {
                opacity: 0.5;
                cursor: not-allowed;
            }

            .page-info {
                color: #666;
                font-size: 14px;
            }

            .error-message {
                background: #fee;
                color: #c00;
                padding: 12px 16px;
                border-radius: 6px;
                margin-bottom: 16px;
                border: 1px solid #fcc;
            }

            .success-message {
                background: #efe;
                color: #060;
                padding: 12px 16px;
                border-radius: 6px;
                margin-bottom: 16px;
                border: 1px solid #cfc;
            }

            .empty-state {
                text-align: center;
                padding: 60px 20px;
                color: #999;
            }

            .empty-state-icon {
                font-size: 48px;
                margin-bottom: 16px;
            }

            .loading {
                text-align: center;
                padding: 40px;
                color: #666;
            }

            .spinner {
                display: inline-block;
                width: 24px;
                height: 24px;
                border: 3px solid #f0f0f0;
                border-top-color: #667eea;
                border-radius: 50%;
                animation: spin 1s linear infinite;
            }

            @keyframes spin {
                to { transform: rotate(360deg); }
            }

            .schema-section {
                margin-top: 16px;
            }

            .schema-toggle {
                cursor: pointer;
                color: #667eea;
                font-size: 13px;
                display: flex;
                align-items: center;
                gap: 4px;
            }

            .schema-toggle:hover {
                text-decoration: underline;
            }

            .schema-content {
                display: none;
                margin-top: 12px;
                background: #f8f9fa;
                border-radius: 6px;
                padding: 12px;
            }

            .schema-content.visible {
                display: block;
            }

            .schema-table {
                font-size: 12px;
            }

            .schema-table th {
                background: #e8f0fe;
                padding: 8px 12px;
            }

            .schema-table td {
                padding: 6px 12px;
            }

            .column-type {
                color: #764ba2;
                font-family: monospace;
            }

            .column-pk {
                background: #ffd700;
                color: #333;
                padding: 2px 6px;
                border-radius: 3px;
                font-size: 10px;
                font-weight: 600;
            }

            .column-notnull {
                background: #e0e0e0;
                color: #666;
                padding: 2px 6px;
                border-radius: 3px;
                font-size: 10px;
            }

            .tabs {
                display: flex;
                gap: 4px;
                margin-bottom: 12px;
            }

            .tab {
                padding: 8px 16px;
                border: none;
                background: #f0f0f0;
                border-radius: 6px 6px 0 0;
                cursor: pointer;
                font-size: 13px;
                transition: all 0.2s;
            }

            .tab.active {
                background: white;
                font-weight: 500;
            }

            .tab:hover:not(.active) {
                background: #e8e8e8;
            }

            /* SQL History styles */
            .query-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 8px;
            }

            .history-container {
                position: relative;
            }

            .history-btn {
                padding: 6px 12px;
                border: 1px solid #ddd;
                background: white;
                border-radius: 4px;
                cursor: pointer;
                font-size: 13px;
                transition: all 0.2s;
                display: flex;
                align-items: center;
                gap: 6px;
            }

            .history-btn:hover {
                background: #f5f5f5;
                border-color: #ccc;
            }

            .history-dropdown {
                display: none;
                position: absolute;
                top: 100%;
                right: 0;
                margin-top: 4px;
                background: white;
                border: 1px solid #ddd;
                border-radius: 6px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.15);
                z-index: 100;
                min-width: 400px;
                max-width: 600px;
                max-height: 400px;
                overflow: hidden;
                display: none;
                flex-direction: column;
            }

            .history-dropdown.visible {
                display: flex;
            }

            .history-header {
                padding: 12px 16px;
                border-bottom: 1px solid #e0e0e0;
                display: flex;
                justify-content: space-between;
                align-items: center;
                background: #f8f9fa;
            }

            .history-title {
                font-weight: 600;
                font-size: 13px;
                color: #555;
            }

            .history-clear {
                padding: 4px 8px;
                border: none;
                background: #fee;
                color: #c00;
                border-radius: 4px;
                cursor: pointer;
                font-size: 12px;
                transition: all 0.2s;
            }

            .history-clear:hover {
                background: #fcc;
            }

            .history-list {
                flex: 1;
                overflow-y: auto;
                list-style: none;
            }

            .history-item {
                padding: 10px 16px;
                border-bottom: 1px solid #f0f0f0;
                cursor: pointer;
                transition: background-color 0.2s;
                font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
                font-size: 12px;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
            }

            .history-item:hover {
                background-color: #e8f0fe;
            }

            .history-item:last-child {
                border-bottom: none;
            }

            .history-time {
                font-size: 10px;
                color: #999;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                margin-bottom: 4px;
            }

            .history-sql {
                color: #333;
            }

            .history-empty {
                padding: 20px;
                text-align: center;
                color: #999;
                font-size: 13px;
            }

            .history-badge {
                background: #667eea;
                color: white;
                font-size: 10px;
                padding: 2px 6px;
                border-radius: 10px;
                margin-left: 4px;
            }
        </style>
    </head>
    <body>
        <div class="header">
            <span class="header-title">SwiftStore Admin</span>
            <nav class="header-nav">
                <a href="/admin" class="active">Database</a>
                <a href="/files">Files</a>
            </nav>
        </div>
        <div class="container">
            <div class="sidebar">
                <div class="sidebar-title">Tables</div>
                <ul class="table-list" id="tableList">
                    <li class="loading"><div class="spinner"></div></li>
                </ul>
            </div>
            <div class="main-content">
                <div class="query-section">
                    <div class="query-header">
                        <div class="query-label">SQL Query</div>
                        <div class="history-container">
                            <button class="history-btn" onclick="toggleHistory()">
                                <span>History</span>
                                <span class="history-badge" id="historyBadge" style="display: none;">0</span>
                            </button>
                            <div class="history-dropdown" id="historyDropdown">
                                <div class="history-header">
                                    <span class="history-title">SQL History</span>
                                    <button class="history-clear" onclick="clearHistory()">Clear All</button>
                                </div>
                                <ul class="history-list" id="historyList">
                                    <li class="history-empty">No history yet</li>
                                </ul>
                            </div>
                        </div>
                    </div>
                    <textarea class="query-input" id="queryInput" placeholder="SELECT * FROM table_name LIMIT 100"></textarea>
                    <button class="btn btn-primary" onclick="executeQuery()">Execute</button>
                    <button class="btn btn-secondary" onclick="clearQuery()">Clear</button>
                </div>

                <div class="data-section">
                    <div class="data-header">
                        <div>
                            <span class="data-title" id="dataTitle">Select a table</span>
                            <span class="data-info" id="dataInfo"></span>
                        </div>
                        <div style="display: flex; align-items: center; gap: 16px;">
                            <button class="btn-copy" id="downloadCsvBtn" onclick="downloadCSV()" style="display: none;">Download CSV</button>
                            <div class="schema-toggle" id="schemaToggle" onclick="toggleSchema()">
                                <span id="schemaArrow">&#9654;</span> View Schema
                            </div>
                        </div>
                    </div>

                    <div class="schema-content" id="schemaContent">
                        <table class="schema-table">
                            <thead>
                                <tr>
                                    <th>Column</th>
                                    <th>Type</th>
                                    <th>Constraints</th>
                                    <th>Default</th>
                                </tr>
                            </thead>
                            <tbody id="schemaBody"></tbody>
                        </table>
                    </div>

                    <div class="table-container" id="tableContainer">
                        <div class="empty-state">
                            <div class="empty-state-icon">&#128202;</div>
                            <p>Select a table from the sidebar or run a query</p>
                        </div>
                    </div>

                    <div class="pagination" id="pagination" style="display: none;">
                        <button onclick="prevPage()" id="prevBtn">&lt; Previous</button>
                        <span class="page-info" id="pageInfo">Page 1</span>
                        <button onclick="nextPage()" id="nextBtn">Next &gt;</button>
                    </div>
                </div>
            </div>
        </div>

        <!-- Value Detail Modal -->
        <div class="modal-overlay" id="valueModal" onclick="closeModalOnOverlay(event)">
            <div class="modal">
                <div class="modal-header">
                    <span class="modal-title" id="modalTitle">Value Details</span>
                    <div class="modal-actions">
                        <label class="format-toggle" id="formatToggleLabel" style="display: none;">
                            <input type="checkbox" id="formatToggle" onchange="toggleJsonFormat()">
                            Format JSON
                        </label>
                        <label class="format-toggle" id="timestampToggleLabel" style="display: none;">
                            <input type="checkbox" id="timestampToggle" onchange="toggleTimestampFormat()">
                            Show Time
                        </label>
                        <button class="btn-copy" id="copyBtn" onclick="copyValue()">Copy</button>
                        <button class="modal-close" onclick="closeModal()">&times;</button>
                    </div>
                </div>
                <div class="modal-body">
                    <pre class="modal-content" id="modalContent"></pre>
                </div>
            </div>
        </div>

        <script>
            // State
            let currentTable = null;
            let currentPage = 1;
            let pageSize = 50;
            let totalRows = 0;
            let schema = null;
            let isCustomQuery = false;
            let modalRawValue = null;
            let modalParsedJson = null;

            // API calls
            async function fetchSchema() {
                const response = await fetch('/api/schema');
                schema = await response.json();
                renderTableList();
            }

            async function fetchTableData(tableName, page = 1) {
                // Use backend pagination - don't add LIMIT/OFFSET to SQL
                const query = `SELECT * FROM ${tableName}`;

                const response = await fetch('/api/query', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ sql: query, page: page, pageSize: pageSize })
                });

                return response.json();
            }

            async function executeCustomQuery(sql) {
                const response = await fetch('/api/query', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ sql: sql })
                });

                return response.json();
            }

            // Render functions
            function renderTableList() {
                const list = document.getElementById('tableList');

                if (!schema || !schema.tables || schema.tables.length === 0) {
                    list.innerHTML = '<li class="empty-state" style="padding: 20px; text-align: center; color: #999;">No tables found</li>';
                    return;
                }

                list.innerHTML = schema.tables.map(table => `
                    <li class="table-item ${currentTable === table.name ? 'active' : ''}"
                        onclick="selectTable('${table.name}')">
                        <svg class="table-icon" viewBox="0 0 24 24" fill="currentColor">
                            <path d="M3 3h18v18H3V3zm16 2H5v4h14V5zm0 6H5v4h14v-4zm0 6H5v4h14v-4z"/>
                        </svg>
                        ${table.name}
                    </li>
                `).join('');
            }

            function renderTable(data) {
                const container = document.getElementById('tableContainer');
                const downloadBtn = document.getElementById('downloadCsvBtn');

                if (!data.success) {
                    container.innerHTML = `<div class="error-message">${data.error || 'Query failed'}</div>`;
                    downloadBtn.style.display = 'none';
                    return;
                }

                if (!data.data || data.data.length === 0) {
                    container.innerHTML = `
                        <div class="empty-state">
                            <div class="empty-state-icon">&#128466;</div>
                            <p>No data found</p>
                        </div>
                    `;
                    downloadBtn.style.display = 'none';
                    return;
                }

                // Show download button when we have data
                downloadBtn.style.display = 'inline-block';

                const columns = Object.keys(data.data[0]);

                // Store data for double-click access
                window._tableData = data.data;
                window._tableColumns = columns;

                // Get column types from schema
                function getColumnType(colName) {
                    if (!currentTable || !schema || !schema.tables) return null;
                    const tableSchema = schema.tables.find(t => t.name === currentTable);
                    if (!tableSchema) return null;
                    const col = tableSchema.columns.find(c => c.name === colName);
                    return col ? col.type : null;
                }

                const html = `
                    <table>
                        <thead>
                            <tr>
                                ${columns.map(col => {
                                    const colType = getColumnType(col);
                                    const typeHtml = colType ? `<div class="column-type-hint">${escapeHtml(colType)}</div>` : '';
                                    return `<th><div>${escapeHtml(col)}</div>${typeHtml}</th>`;
                                }).join('')}
                            </tr>
                        </thead>
                        <tbody>
                            ${data.data.map((row, rowIndex) => `
                                <tr>
                                    ${columns.map((col, colIndex) => {
                                        const rawValue = row[col];
                                        const displayValue = formatDisplayValue(rawValue);
                                        if (displayValue === null) {
                                            return `<td class="null-value" data-row="${rowIndex}" data-col="${colIndex}">NULL</td>`;
                                        }
                                        return `<td title="${escapeHtml(String(displayValue))}" data-row="${rowIndex}" data-col="${colIndex}">${escapeHtml(String(displayValue))}</td>`;
                                    }).join('')}
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                `;

                container.innerHTML = html;

                // Add double-click handler for cells
                container.querySelectorAll('td').forEach(td => {
                    td.addEventListener('dblclick', function() {
                        const rowIndex = parseInt(this.dataset.row);
                        const colIndex = parseInt(this.dataset.col);
                        const colName = window._tableColumns[colIndex];
                        const rawValue = window._tableData[rowIndex][colName];
                        showValueModal(rawValue, colName);
                    });
                });
            }

            function renderSchema(tableName) {
                const tableSchema = schema.tables.find(t => t.name === tableName);
                if (!tableSchema) return;

                const body = document.getElementById('schemaBody');
                body.innerHTML = tableSchema.columns.map(col => `
                    <tr>
                        <td><strong>${escapeHtml(col.name)}</strong></td>
                        <td class="column-type">${escapeHtml(col.type)}</td>
                        <td>
                            ${col.isPrimaryKey ? '<span class="column-pk">PK</span>' : ''}
                            ${col.isNotNull ? '<span class="column-notnull">NOT NULL</span>' : ''}
                        </td>
                        <td>${col.defaultValue ? escapeHtml(col.defaultValue) : '<span class="null-value">-</span>'}</td>
                    </tr>
                `).join('');
            }

            function updatePagination() {
                const pagination = document.getElementById('pagination');
                const pageInfo = document.getElementById('pageInfo');
                const prevBtn = document.getElementById('prevBtn');
                const nextBtn = document.getElementById('nextBtn');

                if (isCustomQuery || totalRows === 0) {
                    pagination.style.display = 'none';
                    return;
                }

                pagination.style.display = 'flex';
                const totalPages = Math.ceil(totalRows / pageSize);
                pageInfo.textContent = `Page ${currentPage} of ${totalPages} (${totalRows} rows)`;

                prevBtn.disabled = currentPage <= 1;
                nextBtn.disabled = currentPage >= totalPages;
            }

            // Event handlers
            async function selectTable(tableName) {
                currentTable = tableName;
                currentPage = 1;
                isCustomQuery = false;

                renderTableList();

                document.getElementById('dataTitle').textContent = tableName;
                document.getElementById('dataInfo').textContent = 'Loading...';
                document.getElementById('tableContainer').innerHTML = '<div class="loading"><div class="spinner"></div></div>';

                // Update query input with default query
                document.getElementById('queryInput').value = `SELECT * FROM ${tableName}`;

                // Render schema
                renderSchema(tableName);

                // Fetch data (pagination info included in response)
                const data = await fetchTableData(tableName, currentPage);

                if (data.pagination) {
                    totalRows = data.pagination.totalRows;
                    document.getElementById('dataInfo').textContent = `(${totalRows} total rows)`;
                } else {
                    totalRows = data.data ? data.data.length : 0;
                    document.getElementById('dataInfo').textContent = `(${totalRows} rows)`;
                }

                renderTable(data);
                updatePagination();
            }

            async function executeQuery() {
                const sql = document.getElementById('queryInput').value.trim();
                if (!sql) return;

                isCustomQuery = true;
                totalRows = 0;

                // Update UI
                document.getElementById('dataTitle').textContent = 'Query Result';
                document.getElementById('dataInfo').textContent = '';
                document.getElementById('tableContainer').innerHTML = '<div class="loading"><div class="spinner"></div></div>';

                const result = await executeCustomQuery(sql);

                if (result.success) {
                    document.getElementById('dataInfo').textContent = `(${result.data ? result.data.length : 0} rows returned)`;
                    // Add to history on successful execution
                    addToHistory(sql);
                }

                renderTable(result);
                updatePagination();
            }

            function clearQuery() {
                document.getElementById('queryInput').value = '';
                if (currentTable) {
                    document.getElementById('queryInput').value = `SELECT * FROM ${currentTable}`;
                }
            }

            async function prevPage() {
                if (currentPage > 1 && currentTable) {
                    currentPage--;
                    const data = await fetchTableData(currentTable, currentPage);
                    renderTable(data);
                    updatePagination();
                }
            }

            async function nextPage() {
                const totalPages = Math.ceil(totalRows / pageSize);
                if (currentPage < totalPages && currentTable) {
                    currentPage++;
                    const data = await fetchTableData(currentTable, currentPage);
                    renderTable(data);
                    updatePagination();
                }
            }

            function toggleSchema() {
                const content = document.getElementById('schemaContent');
                const arrow = document.getElementById('schemaArrow');

                if (content.classList.contains('visible')) {
                    content.classList.remove('visible');
                    arrow.innerHTML = '&#9654;';
                } else {
                    content.classList.add('visible');
                    arrow.innerHTML = '&#9660;';
                }
            }

            function escapeHtml(text) {
                const div = document.createElement('div');
                div.textContent = text;
                return div.innerHTML;
            }

            // Format value for display, handling blob data specially
            function formatValue(value) {
                if (value === null) return null;

                // Check if it's a blob object from backend
                if (typeof value === 'object' && value._type === 'blob') {
                    return decodeBlobValue(value.base64, parseInt(value.size));
                }

                return String(value);
            }

            // Format value for table cell display, including timestamp formatting
            function formatDisplayValue(value) {
                if (value === null) return null;

                // Check if it's a blob object from backend
                if (typeof value === 'object' && value._type === 'blob') {
                    return decodeBlobValue(value.base64, parseInt(value.size));
                }

                // Try to parse as timestamp
                const timestamp = tryParseTimestamp(value);
                if (timestamp) {
                    return timestamp.short;
                }

                return String(value);
            }

            // Decode base64 blob data as common types
            function decodeBlobValue(base64, size) {
                try {
                    const binary = atob(base64);
                    const bytes = new Uint8Array(binary.length);
                    for (let i = 0; i < binary.length; i++) {
                        bytes[i] = binary.charCodeAt(i);
                    }

                    // Try UUID (16 bytes)
                    if (bytes.length === 16) {
                        const hex = Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
                        const uuid = `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`.toUpperCase();
                        return uuid;
                    }

                    // Try UTF-8 string
                    const decoder = new TextDecoder('utf-8', { fatal: true });
                    try {
                        const str = decoder.decode(bytes);
                        // Check if printable
                        const isPrintable = str.split('').every(c => {
                            const code = c.charCodeAt(0);
                            return code >= 32 || code === 9 || code === 10 || code === 13;
                        });
                        if (str.length > 0 && isPrintable) {
                            return str;
                        }
                    } catch (e) {
                        // Not valid UTF-8
                    }

                    // Show as blob with size
                    return `[BLOB: ${size} bytes]`;
                } catch (e) {
                    return `[BLOB: ${size} bytes]`;
                }
            }

            // Try to parse number as timestamp
            function tryParseTimestamp(value) {
                const num = typeof value === 'number' ? value : parseFloat(value);
                if (isNaN(num) || !isFinite(num) || num <= 0) return null;

                // Define reasonable date range: 2000-01-01 to 2100-01-01
                const minSeconds = 946684800;      // 2000-01-01
                const maxSeconds = 4102444800;     // 2100-01-01
                const minMillis = minSeconds * 1000;
                const maxMillis = maxSeconds * 1000;

                let date = null;
                let type = null;

                // Try as seconds timestamp (10 digits)
                if (num >= minSeconds && num <= maxSeconds) {
                    date = new Date(num * 1000);
                    type = 'seconds';
                }
                // Try as milliseconds timestamp (13 digits)
                else if (num >= minMillis && num <= maxMillis) {
                    date = new Date(num);
                    type = 'milliseconds';
                }

                if (date && !isNaN(date.getTime())) {
                    // Format as YYYY-MM-DD HH:mm:ss
                    const pad = n => String(n).padStart(2, '0');
                    const short = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
                    return {
                        date: date,
                        type: type,
                        short: short,
                        formatted: short
                    };
                }
                return null;
            }

            // Modal state for timestamp toggle
            let modalTimestamp = null;
            let modalDisplayValue = null;

            // Modal functions
            function showValueModal(rawValue, columnName) {
                modalRawValue = rawValue;
                modalParsedJson = null;
                modalTimestamp = null;
                modalDisplayValue = null;

                const modal = document.getElementById('valueModal');
                const title = document.getElementById('modalTitle');
                const content = document.getElementById('modalContent');
                const formatToggleLabel = document.getElementById('formatToggleLabel');
                const formatToggle = document.getElementById('formatToggle');
                const timestampToggleLabel = document.getElementById('timestampToggleLabel');
                const timestampToggle = document.getElementById('timestampToggle');

                title.textContent = columnName || 'Value Details';

                // Get display value (handles blob decoding)
                modalDisplayValue = formatValue(rawValue);

                // For blob that decoded to string, also try the original base64 decoded content
                let valuesToTryJson = [modalDisplayValue];
                if (typeof rawValue === 'object' && rawValue._type === 'blob') {
                    // Also try direct blob content as potential JSON
                    try {
                        const binary = atob(rawValue.base64);
                        const bytes = new Uint8Array(binary.length);
                        for (let i = 0; i < binary.length; i++) {
                            bytes[i] = binary.charCodeAt(i);
                        }
                        const decoder = new TextDecoder('utf-8', { fatal: true });
                        const blobStr = decoder.decode(bytes);
                        if (blobStr !== modalDisplayValue) {
                            valuesToTryJson.push(blobStr);
                        }
                    } catch (e) {}
                }

                // Try to parse as JSON (but not simple numbers/strings - those should be handled separately)
                let foundJson = false;
                for (const val of valuesToTryJson) {
                    if (typeof val === 'string') {
                        try {
                            const parsed = JSON.parse(val);
                            // Only treat as JSON if it's an object or array, not primitive values
                            if (typeof parsed === 'object' && parsed !== null) {
                                modalParsedJson = parsed;
                                formatToggleLabel.style.display = 'flex';
                                formatToggle.checked = true;
                                timestampToggleLabel.style.display = 'none';
                                content.innerHTML = syntaxHighlightJson(JSON.stringify(modalParsedJson, null, 2));
                                foundJson = true;
                                break;
                            }
                        } catch (e) {
                            // Not JSON, continue
                        }
                    }
                }

                if (!foundJson) {
                    formatToggleLabel.style.display = 'none';

                    // Try to parse as timestamp if it's a number
                    modalTimestamp = tryParseTimestamp(rawValue);
                    if (modalTimestamp) {
                        timestampToggleLabel.style.display = 'flex';
                        timestampToggle.checked = true;
                        content.textContent = modalTimestamp.formatted;
                    } else {
                        timestampToggleLabel.style.display = 'none';
                        content.textContent = modalDisplayValue;
                    }
                }

                modal.classList.add('visible');
            }

            function toggleTimestampFormat() {
                const content = document.getElementById('modalContent');
                const timestampToggle = document.getElementById('timestampToggle');

                if (timestampToggle.checked && modalTimestamp) {
                    content.textContent = modalTimestamp.formatted;
                } else {
                    content.textContent = modalDisplayValue;
                }
            }

            function closeModal() {
                document.getElementById('valueModal').classList.remove('visible');
            }

            function copyValue() {
                const content = document.getElementById('modalContent');
                const copyBtn = document.getElementById('copyBtn');

                // Get text content (strips HTML tags from syntax highlighted JSON)
                const textToCopy = content.textContent;

                function showSuccess() {
                    copyBtn.textContent = 'Copied!';
                    copyBtn.classList.add('copied');
                    setTimeout(() => {
                        copyBtn.textContent = 'Copy';
                        copyBtn.classList.remove('copied');
                    }, 2000);
                }

                function showError() {
                    copyBtn.textContent = 'Failed';
                    setTimeout(() => {
                        copyBtn.textContent = 'Copy';
                    }, 2000);
                }

                // Try modern clipboard API first, fallback to execCommand
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(textToCopy).then(showSuccess).catch(showError);
                } else {
                    // Fallback for non-HTTPS environments
                    const textarea = document.createElement('textarea');
                    textarea.value = textToCopy;
                    textarea.style.position = 'fixed';
                    textarea.style.opacity = '0';
                    document.body.appendChild(textarea);
                    textarea.select();
                    try {
                        document.execCommand('copy');
                        showSuccess();
                    } catch (err) {
                        showError();
                    }
                    document.body.removeChild(textarea);
                }
            }

            function downloadCSV() {
                if (!window._tableData || !window._tableColumns) return;

                const columns = window._tableColumns;
                const data = window._tableData;

                // Build CSV content
                const csvRows = [];

                // Header row
                csvRows.push(columns.map(col => escapeCsvValue(col)).join(','));

                // Data rows
                for (const row of data) {
                    const values = columns.map(col => {
                        const rawValue = row[col];
                        const displayValue = formatValue(rawValue);
                        return escapeCsvValue(displayValue === null ? '' : String(displayValue));
                    });
                    csvRows.push(values.join(','));
                }

                const csvContent = csvRows.join('\\n');

                // Create blob and download
                const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
                const url = URL.createObjectURL(blob);
                const link = document.createElement('a');
                link.href = url;

                // Generate filename
                const timestamp = new Date().toISOString().slice(0, 19).replace(/[:-]/g, '');
                const tableName = currentTable || 'query_result';
                link.download = `${tableName}_${timestamp}.csv`;

                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
                URL.revokeObjectURL(url);
            }

            function escapeCsvValue(value) {
                if (value === null || value === undefined) return '';
                const str = String(value);
                // Escape quotes and wrap in quotes if contains comma, quote, or newline
                if (str.includes(',') || str.includes('"') || str.includes('\\n') || str.includes('\\r')) {
                    return '"' + str.replace(/"/g, '""') + '"';
                }
                return str;
            }

            function closeModalOnOverlay(event) {
                if (event.target.id === 'valueModal') {
                    closeModal();
                }
            }

            function toggleJsonFormat() {
                const formatToggle = document.getElementById('formatToggle');
                const content = document.getElementById('modalContent');

                if (modalParsedJson !== null) {
                    if (formatToggle.checked) {
                        content.innerHTML = syntaxHighlightJson(JSON.stringify(modalParsedJson, null, 2));
                    } else {
                        content.textContent = JSON.stringify(modalParsedJson);
                    }
                }
            }

            function syntaxHighlightJson(json) {
                // Escape HTML first
                json = json.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                // Apply syntax highlighting
                return json.replace(
                    /("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\\s*:)?|\\b(true|false|null)\\b|-?\\d+(?:\\.\\d*)?(?:[eE][+\\-]?\\d+)?)/g,
                    function (match) {
                        let cls = 'json-number';
                        if (/^"/.test(match)) {
                            if (/:$/.test(match)) {
                                cls = 'json-key';
                            } else {
                                cls = 'json-string';
                            }
                        } else if (/true|false/.test(match)) {
                            cls = 'json-boolean';
                        } else if (/null/.test(match)) {
                            cls = 'json-null';
                        }
                        return '<span class="' + cls + '">' + match + '</span>';
                    }
                );
            }

            // SQL History functions
            const HISTORY_KEY = 'swiftstore_sql_history';
            const MAX_HISTORY = 50;

            function getHistory() {
                try {
                    const data = localStorage.getItem(HISTORY_KEY);
                    return data ? JSON.parse(data) : [];
                } catch (e) {
                    return [];
                }
            }

            function saveHistory(history) {
                try {
                    localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
                } catch (e) {
                    console.error('Failed to save history:', e);
                }
            }

            function addToHistory(sql) {
                const trimmedSql = sql.trim();
                if (!trimmedSql) return;

                let history = getHistory();

                // Remove duplicate if exists
                history = history.filter(item => item.sql !== trimmedSql);

                // Add new entry at the beginning
                history.unshift({
                    sql: trimmedSql,
                    time: Date.now()
                });

                // Limit history size
                if (history.length > MAX_HISTORY) {
                    history = history.slice(0, MAX_HISTORY);
                }

                saveHistory(history);
                updateHistoryUI();
            }

            function clearHistory() {
                if (confirm('Clear all SQL history?')) {
                    localStorage.removeItem(HISTORY_KEY);
                    updateHistoryUI();
                    toggleHistory(); // Close dropdown
                }
            }

            function toggleHistory() {
                const dropdown = document.getElementById('historyDropdown');
                dropdown.classList.toggle('visible');

                // Close when clicking outside
                if (dropdown.classList.contains('visible')) {
                    setTimeout(() => {
                        document.addEventListener('click', closeHistoryOnClickOutside);
                    }, 0);
                }
            }

            function closeHistoryOnClickOutside(e) {
                const container = document.querySelector('.history-container');
                if (!container.contains(e.target)) {
                    document.getElementById('historyDropdown').classList.remove('visible');
                    document.removeEventListener('click', closeHistoryOnClickOutside);
                }
            }

            function selectHistoryItem(sql) {
                document.getElementById('queryInput').value = sql;
                document.getElementById('historyDropdown').classList.remove('visible');
                document.removeEventListener('click', closeHistoryOnClickOutside);
            }

            function formatHistoryTime(timestamp) {
                const date = new Date(timestamp);
                const now = new Date();
                const diff = now - date;

                if (diff < 60000) return 'Just now';
                if (diff < 3600000) return Math.floor(diff / 60000) + 'm ago';
                if (diff < 86400000) return Math.floor(diff / 3600000) + 'h ago';
                if (diff < 604800000) return Math.floor(diff / 86400000) + 'd ago';

                return date.toLocaleDateString();
            }

            function updateHistoryUI() {
                const history = getHistory();
                const list = document.getElementById('historyList');
                const badge = document.getElementById('historyBadge');

                // Update badge
                if (history.length > 0) {
                    badge.textContent = history.length;
                    badge.style.display = 'inline';
                } else {
                    badge.style.display = 'none';
                }

                // Update list
                if (history.length === 0) {
                    list.innerHTML = '<li class="history-empty">No history yet</li>';
                    return;
                }

                list.innerHTML = history.map((item, index) => `
                    <li class="history-item" data-index="${index}">
                        <div class="history-time">${formatHistoryTime(item.time)}</div>
                        <div class="history-sql">${escapeHtml(item.sql)}</div>
                    </li>
                `).join('');

                // Attach click handlers
                list.querySelectorAll('.history-item').forEach(li => {
                    li.addEventListener('click', function() {
                        const index = parseInt(this.dataset.index);
                        selectHistoryItem(history[index].sql);
                    });
                });
            }

            // Keyboard shortcuts
            document.getElementById('queryInput').addEventListener('keydown', function(e) {
                if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
                    executeQuery();
                }
            });

            // Close modal on Escape
            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') {
                    closeModal();
                    document.getElementById('historyDropdown').classList.remove('visible');
                }
            });

            // Initialize
            fetchSchema();
            updateHistoryUI();
        </script>
    </body>
    </html>
    """
}
