const std = @import("std");
const rl = @import("raylib");
const Io = std.Io;

const zig_zag_zoe = @import("zig_zag_zoe");

const assert = std.debug.assert;
const log = std.log;

const Layout = struct {
    const screen_width: u16 = 900;
    const screen_height: u16 = 900;

    const grid_size: i32 = 3;
    const cell_size: i32 = @divExact(screen_width, grid_size);
};

comptime {
    assert(Layout.screen_width % 3 == 0);
    assert(Layout.screen_height % 3 == 0);
}

const Status = enum { started, x_won, o_won, tie };
const Screen = enum { welcome, game, ending };
const Theme = struct {
    const color = rl.Color.light_gray;
    const thickness_px: i32 = 10;
    const font_size_px: i32 = 50;
    const font_spacing_px: i32 = 0;
};

comptime {
    assert(Theme.thickness_px % 2 == 0);
}

var font: rl.Font = undefined;

pub const Turn = enum { x, o };
pub const Board = [Layout.grid_size][Layout.grid_size]?Turn;

const WinnerLine = struct {
    start: rl.Vector2,
    end: rl.Vector2,
    current: rl.Vector2,
};

const Game = struct {
    board: Board,
    turn: Turn,
    status: Status,
    winner_line: ?WinnerLine = null,
    active_screen: Screen = .welcome,
};

var game: Game = undefined;

fn init_game() void {
    game = Game{
        .board = .{.{null} ** 3} ** 3,
        .turn = .x,
        .status = .started,
    };
}
fn next_turn() void {
    game.turn = switch (game.turn) {
        .x => .o,
        .o => .x,
    };
}
fn find_line_winner(first: ?Turn, second: ?Turn, third: ?Turn) ?Turn {
    if (first == second and second == third) return first;
    return null;
}

fn cell_center(x: usize, y: usize) rl.Vector2 {
    const half_cell_size = Layout.cell_size / 2;

    // Swapped values
    return rl.Vector2{
        .x = @floatFromInt((y * Layout.cell_size) + half_cell_size),
        .y = @floatFromInt((x * Layout.cell_size) + half_cell_size),
    };
}

fn set_winner_line(
    first_cell_x: usize,
    first_cell_y: usize,
    last_cell_x: usize,
    last_cell_y: usize,
) void {
    log.debug("winner line ({}, {}) to ({}, {})", .{ first_cell_x, first_cell_y, last_cell_x, last_cell_y });

    const start = cell_center(first_cell_x, first_cell_y);

    game.winner_line = .{ .start = start, .current = start, .end = cell_center(last_cell_x, last_cell_y) };
}

fn find_winner() ?Turn {
    for (0..Layout.grid_size) |index| {
        if (find_line_winner(game.board[index][0], game.board[index][1], game.board[index][2])) |turn| {
            set_winner_line(index, 0, index, 2);
            return turn;
        }
        if (find_line_winner(game.board[0][index], game.board[1][index], game.board[2][index])) |turn| {
            set_winner_line(0, index, 2, index);
            return turn;
        }
    }
    if (find_line_winner(game.board[0][0], game.board[1][1], game.board[2][2])) |turn| {
        set_winner_line(0, 0, 2, 2);
        return turn;
    }
    if (find_line_winner(game.board[0][2], game.board[1][1], game.board[2][0])) |turn| {
        set_winner_line(0, 2, 2, 0);
        return turn;
    }

    return null;
}

fn is_board_full() bool {
    for (game.board) |row| {
        for (row) |cell| {
            if (cell == null) return false;
        }
    }
    return true;
}

fn update_status() void {
    if (find_winner()) |turn| {
        game.status = switch (turn) {
            .x => .x_won,
            .o => .o_won,
        };
    }

    if (is_board_full()) {
        game.status = .tie;
        game.active_screen = .ending;
    }
    log.debug("game status updated: {}", .{game.status});
}

pub fn take_position(x: u8, y: u8) error{PositionOccupied}!void {
    assert(x < Layout.grid_size);
    assert(y < Layout.grid_size);

    const cell = &game.board[x][y];
    if (cell.* != null) {
        log.debug("position ({}, {}) already occupied", .{ x, y });
        return error.PositionOccupied;
    }

    const turn = game.turn;
    cell.* = turn;
    log.debug("position ({}, {}) taken by {}", .{ x, y, turn });

    update_status();
    next_turn();
    assert(game.turn != turn);
}

fn init_window() error{LoadFont}!void {
    rl.initWindow(
        Layout.screen_width,
        Layout.screen_height,
        "Zig Zag Zoe",
    );

    font = try rl.getFontDefault();

    rl.setTargetFPS(60);
}

fn deinit_window() void {
    rl.closeWindow();
    rl.unloadFont(font);
}
fn text_from_mark(mark: Turn) [:0]const u8 {
    return switch (mark) {
        .x => "x",
        .o => "o",
    };
}

fn draw_winner_line() void {
    const line = if (game.winner_line) |*l| l else return;
    const speed = 8;

    line.current.x += std.math.clamp(line.end.x - line.current.x, -speed, speed);
    line.current.y += std.math.clamp(line.end.y - line.current.y, -speed, speed);

    rl.drawLineEx(
        line.start,
        line.current,
        Theme.thickness_px,
        Theme.color,
    );

    if (line.current.x == line.end.x and line.current.y == line.end.y) {
        game.active_screen = .ending;
    }
}

fn draw_centered_text(text: [:0]const u8) void {
    const text_size = rl.measureTextEx(
        font,
        text,
        Theme.font_size_px,
        Theme.font_spacing_px,
    );

    const text_position = rl.Vector2{
        .x = (Layout.screen_width - text_size.x) / 2,
        .y = (Layout.screen_height - text_size.y) / 2,
    };

    rl.drawTextEx(
        font,
        text,
        text_position,
        Theme.font_size_px,
        Theme.font_spacing_px,
        Theme.color,
    );
}

fn draw_board() void {
    const cell_width_px: f32 = @floatFromInt(Layout.screen_width / Layout.grid_size);
    const cell_height_px: f32 = @floatFromInt(Layout.screen_height / Layout.grid_size);

    for (game.board, 0..) |row, row_index| {
        for (row, 0..) |cell, column_index| {
            // If cell is not taken, nothing to set
            const mark = cell orelse continue;
            const text = text_from_mark(mark);

            const row_index_f32: f32 = @floatFromInt(row_index);
            const column_index_f32: f32 = @floatFromInt(column_index);
            const text_font_size = cell_width_px / 2;

            const text_size = rl.measureTextEx(
                font,
                text,
                text_font_size,
                0,
            );

            assert(text_size.x <= cell_width_px);
            assert(text_size.y <= cell_height_px);

            const text_position = rl.Vector2{
                .x = cell_width_px * column_index_f32 + (cell_width_px - text_size.x) / 2,
                .y = cell_height_px * row_index_f32 + (cell_height_px - text_size.y) / 2,
            };

            rl.drawTextEx(
                font,
                text,
                text_position,
                cell_width_px / 2,
                Theme.font_spacing_px,
                Theme.color,
            );
        }
    }
}

fn draw_grid() void {
    const border_offset_px = Theme.thickness_px / 2;
    const cell_width_px: i32 = @intCast(Layout.screen_width / Layout.grid_size);
    const cell_height_px: i32 = @intCast(Layout.screen_height / Layout.grid_size);

    for (1..Layout.grid_size) |line_index| {
        const line_index_i32: i32 = @intCast(line_index);

        const vertical_border_x = cell_width_px * line_index_i32 - border_offset_px;
        rl.drawRectangle(
            vertical_border_x,
            0,
            Theme.thickness_px,
            @intCast(Layout.screen_height),
            Theme.color,
        );

        const horizontal_border_y = cell_height_px * line_index_i32 - border_offset_px;
        rl.drawRectangle(
            0,
            horizontal_border_y,
            @intCast(Layout.screen_width),
            Theme.thickness_px,
            Theme.color,
        );
    }
}

fn update_game() void {
    switch (game.active_screen) {
        .welcome => {
            if (rl.isKeyPressed(.enter) or rl.isMouseButtonPressed(.left)) {
                game.active_screen = .game;
            }
        },
        .game => {
            if (game.status == .started and rl.isMouseButtonPressed(.left)) {
                const mouse_position = rl.getMousePosition();

                const x: u8 = @intFromFloat(@divExact(mouse_position.y, Layout.cell_size));
                const y: u8 = @intFromFloat(@divExact(mouse_position.x, Layout.cell_size));

                take_position(x, y) catch |err| switch (err) {
                    error.PositionOccupied => {},
                };
            }
        },
        .ending => {
            if (rl.isKeyPressed(.r) or rl.isMouseButtonPressed(.left)) {
                init_game();
                game.active_screen = .game;
            }
        },
    }
}

fn draw_game() void {
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(.black);

    switch (game.active_screen) {
        .welcome => {
            draw_centered_text("Welcome! Press enter to start");
        },
        .game => {
            draw_grid();
            draw_board();
            draw_winner_line();
        },
        .ending => {
            switch (game.status) {
                .o_won => draw_centered_text("O won!"),
                .x_won => draw_centered_text("X won!"),
                .tie => draw_centered_text("It's a tie!"),
                .started => {},
            }
        },
    }
}

fn update_draw_frame() void {
    update_game();
    draw_game();
}

pub fn main() !void {
    try init_window();
    defer deinit_window();

    init_game();
    while (!rl.windowShouldClose()) {
        update_draw_frame();
    }
}
