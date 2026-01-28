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
                padding: 16px 24px;
                font-size: 20px;
                font-weight: 600;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                display: flex;
                align-items: center;
                gap: 24px;
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
                    <div class="query-label">SQL Query</div>
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
                        <div class="schema-toggle" id="schemaToggle" onclick="toggleSchema()">
                            <span id="schemaArrow">&#9654;</span> View Schema
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

                if (!data.success) {
                    container.innerHTML = `<div class="error-message">${data.error || 'Query failed'}</div>`;
                    return;
                }

                if (!data.data || data.data.length === 0) {
                    container.innerHTML = `
                        <div class="empty-state">
                            <div class="empty-state-icon">&#128466;</div>
                            <p>No data found</p>
                        </div>
                    `;
                    return;
                }

                const columns = Object.keys(data.data[0]);

                // Store data for double-click access
                window._tableData = data.data;
                window._tableColumns = columns;

                const html = `
                    <table>
                        <thead>
                            <tr>
                                ${columns.map(col => `<th>${escapeHtml(col)}</th>`).join('')}
                            </tr>
                        </thead>
                        <tbody>
                            ${data.data.map((row, rowIndex) => `
                                <tr>
                                    ${columns.map((col, colIndex) => {
                                        const rawValue = row[col];
                                        const value = formatValue(rawValue);
                                        if (value === null) {
                                            return `<td class="null-value" data-row="${rowIndex}" data-col="${colIndex}">NULL</td>`;
                                        }
                                        return `<td title="${escapeHtml(String(value))}" data-row="${rowIndex}" data-col="${colIndex}">${escapeHtml(String(value))}</td>`;
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
                    return {
                        date: date,
                        type: type,
                        formatted: date.toLocaleString() + ' (' + type + ')'
                    };
                }
                return null;
            }

            // Modal functions
            function showValueModal(rawValue, columnName) {
                modalRawValue = rawValue;
                modalParsedJson = null;

                const modal = document.getElementById('valueModal');
                const title = document.getElementById('modalTitle');
                const content = document.getElementById('modalContent');
                const formatToggleLabel = document.getElementById('formatToggleLabel');
                const formatToggle = document.getElementById('formatToggle');

                title.textContent = columnName || 'Value Details';

                // Get display value (handles blob decoding)
                let displayValue = formatValue(rawValue);

                // For blob that decoded to string, also try the original base64 decoded content
                let valuesToTryJson = [displayValue];
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
                        if (blobStr !== displayValue) {
                            valuesToTryJson.push(blobStr);
                        }
                    } catch (e) {}
                }

                // Try to parse as JSON
                let foundJson = false;
                for (const val of valuesToTryJson) {
                    if (typeof val === 'string') {
                        try {
                            modalParsedJson = JSON.parse(val);
                            formatToggleLabel.style.display = 'flex';
                            formatToggle.checked = true;
                            content.innerHTML = syntaxHighlightJson(JSON.stringify(modalParsedJson, null, 2));
                            foundJson = true;
                            break;
                        } catch (e) {
                            // Not JSON, continue
                        }
                    }
                }

                if (!foundJson) {
                    formatToggleLabel.style.display = 'none';

                    // Try to parse as timestamp if it's a number
                    const timestamp = tryParseTimestamp(rawValue);
                    if (timestamp) {
                        content.innerHTML = `<div style="margin-bottom: 12px;"><strong>Original value:</strong> ${escapeHtml(String(displayValue))}</div>` +
                            `<div><strong>As timestamp:</strong> ${escapeHtml(timestamp.formatted)}</div>`;
                    } else {
                        content.textContent = displayValue;
                    }
                }

                modal.classList.add('visible');
            }

            function closeModal() {
                document.getElementById('valueModal').classList.remove('visible');
            }

            function copyValue() {
                const content = document.getElementById('modalContent');
                const copyBtn = document.getElementById('copyBtn');

                // Get text content (strips HTML tags from syntax highlighted JSON)
                const textToCopy = content.textContent;

                navigator.clipboard.writeText(textToCopy).then(() => {
                    // Show success feedback
                    copyBtn.textContent = 'Copied!';
                    copyBtn.classList.add('copied');

                    setTimeout(() => {
                        copyBtn.textContent = 'Copy';
                        copyBtn.classList.remove('copied');
                    }, 2000);
                }).catch(err => {
                    console.error('Failed to copy:', err);
                    copyBtn.textContent = 'Failed';
                    setTimeout(() => {
                        copyBtn.textContent = 'Copy';
                    }, 2000);
                });
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
                }
            });

            // Initialize
            fetchSchema();
        </script>
    </body>
    </html>
    """
}
