`ifndef LAB_SPECIFIC_CONFIG_SVH
`define LAB_SPECIFIC_CONFIG_SVH

   `define INSTANTIATE_TM1638_BOARD_CONTROLLER_MODULE
// `define USE_HCW132_VARIANT_OF_TM1638_BOARD_CONTROLLER_MODULE
// `define SPLIT_TM1638_DIO_INOUT_SIGNAL

   `define DUPLICATE_TM1638_SIGNALS_WITH_REGULAR
// `define CONCAT_REGULAR_SIGNALS_AND_TM1638
// `define CONCAT_TM1638_SIGNALS_AND_REGULAR

// `define EMULATE_DYNAMIC_7SEG_ON_STATIC_WITHOUT_STICKY_FLOPS
//
// Описанная выше динамическая эмуляция дисплея отключена специально: микросхема TM1638
// Сканирует цифры из своей оперативной памяти дисплея, поэтому ПЛИС используется только
// необходимо зафиксировать шаблон каждой цифры один раз (фиксатор регистрируется в
// tm1638_registers). При включенной эмуляции каждая позиция сканирования
// left был отключен, что противоречило обновлению записей контроллера и
// создавало стробоскопический эффект.

   `define INSTANTIATE_GRAPHICS_INTERFACE_MODULE
   `define INSTANTIATE_MICROPHONE_INTERFACE_MODULE
   `define INSTANTIATE_SOUND_OUTPUT_INTERFACE_MODULE

`endif  // `ifndef LAB_SPECIFIC_CONFIG_SVH
