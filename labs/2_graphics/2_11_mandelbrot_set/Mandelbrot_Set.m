% Тестовый скрипт для интерактивного множества Мандельброта.
% ВНУТРЕННЯЯ область отрисовки — РОВНО 1024 x 600 пикселей.
%
% Управление: W/S — вверх/вниз, A/D — влево/вправо, Q — зум+, E — зум-,
%             Esc — закрыть окно (полезно, если заголовок ушёл за экран).

clear; clc; close all;

fprintf('=== Тест mandelbrot_interactive ===\n');

if exist('mandelbrot_interactive', 'file')
    fprintf('[i] Найден mandelbrot_interactive.m; будет вызвана ЛОКАЛЬНАЯ функция.\n');
else
    fprintf('[OK] Используется локальная функция mandelbrot_interactive.\n');
end

figsBefore = findall(0, 'Type', 'figure');
nBefore    = numel(figsBefore);
fprintf('     Открытых фигур до запуска: %d\n', nBefore);

try
    mandelbrot_interactive();
    fprintf('[OK] mandelbrot_interactive() выполнилась без ошибок.\n');
catch err
    rethrow(err);
end

drawnow;
figsAfter = findall(0, 'Type', 'figure');
nAfter    = numel(figsAfter);

if nAfter > nBefore
    fprintf('[OK] Создано новое окно (всего фигур: %d).\n', nAfter);
else
    warning('Новое окно не обнаружено — возможно, оно закрыто слишком быстро.');
end

newFigs = setdiff(figsAfter, figsBefore);
if ~isempty(newFigs)
    f    = newFigs(1);
    axs  = findall(f, 'Type', 'axes');
    imgs = findall(f, 'Type', 'image');
    if isempty(axs)
        warning('В новом окне нет axes.');
    else
        fprintf('[OK] В окне найдено axes: %d.\n', numel(axs));
    end
    if isempty(imgs)
        warning('В новом окне нет объекта image.');
    else
        fprintf('[OK] В окне найдено image-объектов: %d.\n', numel(imgs));
    end
    ip = get(f, 'InnerPosition');
    if numel(ip) >= 4
        fprintf('     InnerPosition нового окна: %d x %d px.\n', ...
            round(ip(3)), round(ip(4)));
    end
end

fprintf('\n=== Проверки завершены ===\n');
fprintf('Управление: W A S D — панорама, Q — зум+, E — зум-, Esc — закрыть.\n');


% =====================================================================
function mandelbrot_interactive()
% MANDELBROT_INTERACTIVE — интерактивное множество Мандельброта.
%
% Внутренняя область отрисовки — РОВНО 1024 x 600 пикселей.
%
% Замечание про монитор 1024x600:
%   клиентская область 1024x600 + заголовок окна ~30 px НЕ помещаются
%   в экран 1024x600. Поэтому заголовок и 1 px по правому/верхнему краю
%   будут за пределами экрана. Сама отрисовка при этом занимает ровно
%   1024x600 пикселей. Закрытие — клавишей Esc.
%   На мониторе большего размера окно видно целиком.

    reqW = 1024;
    reqH = 600;
    targetAspect = reqW / reqH;         % = 1.706666…

    % ---- Параметры алгоритма ----
    maxIter  = 20;
    zoomStep = 0.7;
    panStep  = 0.1;

    % ---- Окно ----
    fig = figure('Name','Mandelbrot | WASD — панорама, Q/E — зум, Esc — закрыть', ...
        'NumberTitle','off','Color','k', ...
        'ToolBar','none','MenuBar','none', ...
        'Resize','off', ...              % фиксируем размер (InnerPosition не сбивается)
        'Units','pixels', ...
        'Position',[1 1 reqW reqH], ...  % черновой внешний размер
        'KeyPressFcn', @keyHandler);
    drawnow;

    % ---- Замер «хрома» окна (заголовок + рамки) ----
    outer = fig.Position;
    inner = fig.InnerPosition;
    if numel(inner) < 4, inner = outer; end
    borderW = max(0, outer(3) - inner(3));
    borderH = max(0, outer(4) - inner(4));

    % ---- Установка ТОЧНОЙ внутренней области 1024x600 ----
    placed = false;
    try
        fig.InnerPosition = [1, 1, reqW, reqH];   % основная попытка
        placed = true;
    catch
        try
            fig.Position = [1, 1, reqW + borderW, reqH + borderH];
            placed = true;
        catch
            placed = false;
        end
    end
    if ~placed
        warning('Не удалось задать InnerPosition; размер может отличаться.');
    end
    drawnow;

    % ---- Проверка фактического размера ----
    innerActual = fig.InnerPosition;
    if numel(innerActual) >= 4
        actualW = round(innerActual(3));
        actualH = round(innerActual(4));
    else
        actualW = reqW; actualH = reqH;
    end

    if actualW ~= reqW || actualH ~= reqH
        warning(['Внутренний размер %dx%d вместо требуемых %dx%d. ' ...
                 'ОС/диспетчер окон ограничил размер.'], ...
                actualW, actualH, reqW, reqH);
    else
        fprintf('Внутренняя область: %d x %d пикселей.\n', ...
                actualW, actualH);
    end

    % ---- Axes занимает ВСЮ внутреннюю область ----
    ax = axes('Parent', fig, 'Position', [0 0 1 1], 'Visible', 'off');
    colormap(ax, jet(256));

    % ---- Сетка 1:1 по пикселям ----
    resW = actualW;                     % = 1024
    resH = actualH;                     % = 600
    pixelAspect = resW / resH;          % ≈ 1.7066667

    % ---- Начальные пределы: diff(xl)/diff(yl) == pixelAspect ----
    xl     = [-2.5, 1.5];
    yRange = diff(xl) / pixelAspect;    % ≈ 2.34375
    yl     = [-yRange/2, yRange/2];

    draw();

    % ================================================================
    function draw()
        w = resW;                       % 1 точка данных == 1 пиксель экрана
        h = resH;

        xv = linspace(xl(1), xl(2), w);
        yv = linspace(yl(1), yl(2), h);
        [X, Y] = meshgrid(xv, yv);
        C = X + 1i*Y;
        Z = zeros(size(C));
        iters  = maxIter * ones(size(C));
        active = true(size(C));

        for k = 1:maxIter
            Z(active)   = Z(active).^2 + C(active);
            escaped     = active & (abs(Z) > 2);
            iters(escaped) = k;
            active      = active & ~escaped;
            if ~any(active(:)); break; end
        end

        data = log(iters + 1);

        imagesc(ax, xv, yv, data);
        axis(ax, 'xy');
        set(ax, 'XLim', xl, 'YLim', yl, 'XTick', [], 'YTick', []);
        set(ax, 'CLim', [0 log(maxIter+1)]);    % = caxis/clim без warning

        title(ax, sprintf('X[%.5f, %.5f]   Y[%.5f, %.5f]   iter = %d   (1024x600)', ...
            xl(1), xl(2), yl(1), yl(2), maxIter), ...
            'Color','w','FontSize',10,'Interpreter','none');
        drawnow;
    end

    % ================================================================
    function keyHandler(~, ev)
        if strcmp(ev.Key, 'escape')                  % закрытие по Esc
            close(fig);
            return;
        end

        dx = panStep * diff(xl);
        dy = panStep * diff(yl);
        cx = mean(xl);
        cy = mean(yl);

        switch lower(ev.Key)
            case 'w',   yl = yl + dy;
            case 's',   yl = yl - dy;
            case 'a',   xl = xl - dx;
            case 'd',   xl = xl + dx;
            case 'q'
                xl = cx + (xl - cx) * zoomStep;
                yl = cy + (yl - cy) * zoomStep;
                % maxIter = maxIter + 1;
            case 'e'
                xl = cx + (xl - cx) / zoomStep;
                yl = cy + (yl - cy) / zoomStep;
                % maxIter = max(1, maxIter - 1);
            otherwise
                return;
        end
        draw();
    end
end