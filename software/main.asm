.model small

;---------------bloque de definiciones---------------
    ;direcciones de periféricos
        PortA equ 0300h
        PortB equ 0302h
        PortC equ 0304h
        Pcc   equ 0306h

        t0   equ 0301h
        t1   equ 0303h
        t2   equ 0305h
        tcc  equ 0307h

        IntA0   equ 0308h
        IntA1   equ 030Ah
    ;--------------------------
    
    ;máquina de estados pricipal
        init     equ 000h   ; estado inicial
        closed   equ 001h   ; estado cerrado
        open     equ 002h   ; estado abierto
    ;---------------------------

    ;máquina de estados secundaria
        displayRef          equ 000h     ; estado para refrescar display
        waitingNoiseDown    equ 001h     ; estado de espera por ruido al pulsar la una tecla
        keyboardScan        equ 002h     ; estado de escaneo de teclado
        waitingNoiseUp      equ 003h     ; estado de espera por ruido al soltar una tecla
    ;---------------------------

    ON  equ 10  ; identificador de tecla ON
    OFF equ 11  ; identificador de tecla OFF
;----------fin de bloque de definiciones-------------

;-----------------bloque de macros-------------------

    wrp macro addr,data  ; macro para escribir en direcciones de periféricos de 8 bits
        push ax
        push dx
            mov dx,addr
            mov al,data
            out dx,al
        pop dx
        pop ax
    endm

    rdp macro addrs,addrp   ; macro para leer direcciones de periféricos  de 8 bits
        push dx
            mov dx,addrp
            in al,dx
            mov addrs,al
        pop dx
    endm

    AddIntVector macro AddrIntV,AddrIntP 
        push ds
		mov ax,0
		mov ds,ax                   ;colocando el segmento de datos en la dirección 0.
        mov si,AddrIntV             ;estableciendo dirección de corrimiento (para el usuario debe ser por mayor que 80h y múltiplo de 4)
		mov [si], offset AddrIntP   ;copiando a dirección de segmento en los primeros dos bytes
		mov [si+2], seg AddrIntP    ;copiando corrimiento en los proximos dos bytes
		pop ds                      ;recuperando segmento de datos 
    endm
;-------------fin de bloque de macros----------------

.data 
    org 00100h
        password db 5 dup(0)    ; vector de contraseña de usuario
        SysPassword db 5 dup(0) ; vector de contraseña del sistema
        countkey db 0           ; contador de caracteres escritos en password
        key db 0                ; variable que identifica la última tecla pulsada
        waitingNoise db 0       ; contador para eliminar ruido de tecla

        countLine db 0         ; variable de conteo de filas en barrido de teclado
        countColumn db 0       ; variable de conteo de columnas en barrido de teclao

        displayCount db 0      ; variable para identificar qué lampara 7seg hay que refrescar

        state  db 0     ; variable para estados de máquina de estados 1
        state2 db 0     ; variable para estados de máquina de estados 2

        OCW1save db 0   ; salva de registro de máscaras de interrupciones


;---fin de bloque de datos


.stack 64h

.code
    org 0ef00h
    main proc far
        mov ax,@data                ;carga al registro ax la dirección deseada para el segmento de datos.
        mov ds,ax                   ;carga el registro base del segmento de datos con la dirección deseada.
        mov es,ax                   ;carga el registro base del segmento extra con la dirección del segmento de datos.
        ;-----confifguración inicial-------
        cli                 ; interrupciones desactivadas.
        ;---------cargando contraseña del sistema----------
            mov SysPassword[0],1
            mov SysPassword[1],2
            mov SysPassword[2],3
            mov SysPassword[3],4
            mov SysPassword[4],5
        ;--------------------------------------------------
        mov displayCount,1  ;limpiando contador de display

        wrp Pcc,10001000b   ; configurando puertos A, B y C(3..0) como salida y C(7..4) como entrada.
        wrp PortA,01111111b      ; limpiando bits de lamparas.
        wrp PortB,03Fh      ; lamparas, leds y bosina apagadas.
        wrp PortC,000h      ; todas las filas del teclado en 0.
        
        wrp tcc,00110110b   ; configurando timer 0 en modo 3 con conteo binario de 16 bits.
        wrp tcc,01010100b   ; configurando timer 1 en modo 2 con conteo binatio de 8  bits.
        wrp tcc,10010100b   ; configurando timer 2 en modo 2 con conteo binatio de 8  bits.

        mov ax,01388h       ; cargando timer 0 con valor para periodo de 5 ms.
        wrp t0,al
        wrp t0,ah
        mov al,064h          ; cargando timer 1 con valor para periodo de 500 ms.
        wrp t1,al
        mov al,4            ; cargando timer 2 con valor para periodo de 2 s.
        wrp t2,al

        AddIntVector 080h,KeyInt        ; configurando vector de interrupción para teclado.
        AddIntVector 084h,T5msint       ; configurando vector de interrupción para temporizador de 5ms.
        AddIntVector 088h,T500msInt     ; configurando vector de interrupción para temporizador de 500ms.
        AddIntVector 08Ch,T2sInt        ; configurando vector de interrupción para temporizador de 2s.

        wrp IntA0,00010011b     ; configurando ICW1.
        wrp IntA1,020h          ; configurando ICW2 (dirección base de vector de interrupciones).
        wrp IntA1,001h          ; configurando ICW4.

        ;-------------------
        labelInit: 
            wrp PortB,03Fh          ; lamparas, leds y bosina apagadas.
            wrp PortC,000h          ; todas las filas del teclado en 0. 
            mov state, init         ; cargando estado inicial
            wrp IntA1,11111100b     ; activando interrupciones de 5ms y teclado en el 8259.
            sti                     ; activando interrupciones en el 8086.
        
            initState:
                cmp key,ON          ; si se detecta la tecla On ir a estado closed.
            jne initState

            loadClosedState:
                mov countkey,0      ; limpiando contador de caracteres de password
                rdp al,PortB        ; cargando puerto b en "al" para modificar bits sin perder el esatdo actual.
                and al,11101111b    ; modificando el bit del el led rojo.
                or  al,00100000b    ; modificando bit de led verde.
                wrp PortB,al        ; encendiendo led rojo y apagando verde.
                mov state,closed    ; cambiando a estado closed.

            closedState:
                cmp key,OFF         ; si se pulsa la tecla off volver al estado apagado inicial
                    je labelInit    ; saltar al estado apagado inicial
                cmp state,open      ; si alguna interrupción no cambia el esatdo closed a open, la máquina de estados no saldrá de este ciclo
            jne closedState

            LoadOpenState:
                rdp al,PortB        ; cargando puerto b en "al" para modificar bits sin perder el esatdo actual.
                and al,11011111b    ; modificando el bit del led verde y la bocina.
                or  al,11010000b    ; modificando el bits de led rojo, verde y temporizadores 1 y 2.
                wrp PortB,al        ; encendiendo led verde, la bocina, los temporizadores y apagando el led rojo.
               
                wrp IntA1,11110000b     ; activando interrupciones de 500ms y 2s en el 8259.

            openState:
                cmp key,OFF         ; si se pulsa la tecla off volver al estado apagado inicial
                    je labelInit    ; saltar al estado apagado inicial
                cmp state,open      ; si alguna interrupción no cambia el esatdo open, la máquina de estados no saldrá de este ciclo
            je openState    
            jmp loadClosedState     ; volviendo a estado closed
        ret
    main endp

;-----------------procedimientos-------------------

    RefDisplay proc near
        push bx
        push ax
        push cx

        wrp PortA,0ffh      ; apagando aprte de cátodos de leds de lámparas
        rdp bl,PortB        ; cagrando valor de puerto B en al
        or bl,00001111b     ; aplicando máscara para apagar todas las lámparas
        wrp PortB,bl        ; apagando las lasmparas

        cmp displayCount,5  ; preguntando si está en la última lámpara
        jne noEndlap
            mov displayCount,1 ;reiniciando contador de display
        noEndlap: 

        mov al,displayCount         ; cargando número de lampara a refrescar
        dec al
        cmp state,OPEN              ; identificando estado para mostrar mensaje
        jne isClosed                ; si no está en estado OPEN cargar el mensaje de "----"
            mov bx,offset msgOn     ; cargando offset de mensaje "OPEN"
            jmp impChar             ; ir a extraer caracter
        isClosed:
            mov bx,offset msgOff    ; cargando offset de mensaje "----" 
        impChar:
            xlat cs:msgOff          ; cargando el segento de código a esta zona  
        
        wrp PortA,al     

        mov bl,01111111b    ; cargando valor inicainicial para rotaciones
        xor cx,cx           ; borrando cx
        mov cl,displayCount ; cargando cantidad de veces a rotar
        rotLoop:
            rol bl,1        ; rotando n veces
        loop rotLoop

        rdp bh,PortB        ; cargando valor del puerto b en ah
        and bl,bh           ; borrando el bit de la lámpara a refrescar
        wrp PortB,bl        ; encendiendo lámpara corresondiente
        inc displayCount    ; incrementar contador de display
        
        pop cx
        pop ax
        pop bx
        ret

        ;tablas de mensajes

        msgOff  db 0bfh ;-
                db 0bfh ;-
                db 0bfh ;-
                db 0bfh ;-
                   
        msgOn   db 11000000b ;O
                db 10001100b ;P
                db 10000110b ;E
                db 11001000b ;N

    RefDisplay endp

    keySweep proc near
        push ax
        push bx
        push cx

        mov countColumn,0   ; limpiando contador de columnas
        mov countLine,0     ; limpiando contador de filas

        mov ah,11111110b    ; cargando el valor inicial de las rotaciones

        mov cx,4            ; cargando cx con 4 para el barrido de las 4 filas
        SweepLoop:  
            mov al,ah       ; aplicando máscara para borrar el bit correspondiente 
            and al,00fh
            wrp PortC,al    ; escribiendo en el puerto c
            rdp al,PortC    ; leyendo puerto C 
            or al,00fh      ; máscara para descartar nible bajo (las filas)
            
            cmp al,0ffh     ; comprovando si hay alguna columna en 0.
            jne keydetected ; saltar si se detecta una tecla

            rol ah,1        ; rotando el bit en 0 para el barrido
            inc countLine   ; incrementando el contador de filas
        loop SweepLoop

        jmp endKeySweep     ; saltar al final de la rutina (no s edetectó la tecla)
        
        keyDetected:
            mov cx,3        ; cargando cx con 3 para el barrido de las 3 colúmnas
            columnSweep:
                rol al,1        ; rotando un bit a la isquierda para cargar MSb en la bandera de acarreo
                jnc calculeKey  ; si el acarreo es 0 salta
                inc countColumn ; incrementando contador de columnas
            loop columnSweep
        
        ; según la distribución de las teclas en este teclado el código de cada 
        ; tecla numérica es igual a countLine*(cantidad_de_columnas)+conutColumn (F*3+C).
        calculeKey:             
            mov al,countLine    ; cargando en al el valor del contador de filas.
            add al,countLine    ; sumar 3 veces  el mismo valor es igual a multiplicar por 3
            add al,countLine    ;
            add al,countColumn  ; adicionando contador de comulnas para terminar la fórmula (F*3+C)
            mov key,al          ; guardando tecla

        ; una vez optenida la tecla hay que identificarla 
        cmp al,ON            ; al comparar con ON (es 10) estoy verificando que la tecla pulsada es o no un número
        jae  endKeySweep     ; salta si es mayor o igual (si es menor indica que es un número)
        cmp state,closed     ; si no está en estado closed no se guarda el número
        jne endKeySweep      ; salir si no estado closed
            xor bx,bx            ; borrando bx
            mov bl,countkey      ; cargando bl con el desplasamiento del vector password
            mov password[bx],al  ; cargando la nueva tecla en el vector password
            inc countkey         ; incrementando contador de caracteres de password

            cmp bl,4             ; al comparar bl con 4 se está comprobando que no está en el último caracter de la contraseña 
            jne endKeySweep      ; si no es igual a cuatro no hay que verificar que la contraseña es correcta
                mov cx,5         ; cargando valor para recorres vector de password
                checkPassword:
                    mov bx,cx               ; obteniendo posición de recorrido
                    dec bx                  ; decrementando en uno
                    mov al,SysPassword[bx]  ; cargando en al el caracter x de la contraseña del sistema
                    mov ah,password[bx]     ; cargando en ah el caracter x de la contraseña del usuario
                    cmp al,ah               ; comparando caracteres
                    jne incorrectPassword   ; si no son iguales la contraseña es incorrecta
                loop checkPassword

                ; si el flujo del programa se encuentuentra en esta línea indica 
                ; que la contraseña es correcta y hay que pasar a estado OPEN

                mov state,OPEN  ; cargando estado OPEN
                jmp endKeySweep ; terminar rutina

            incorrectPassword:
                mov countkey,0  ; si la contraseña es incorrecta se reinicia el contador de caracteres para teclear una nueva clave

        endKeySweep:
        wrp PortC,000h
        pop cx
        pop bx
        pop ax
        ret
    keySweep endp
    
;-----------------interrupciones-------------------
    KeyInt proc
        cmp state2,waitingNoiseDown ; si se encuentra en estado de espera por tecla abajo no se atiende esta interrupción por posible rebote
        je endKeyInt
        cmp state2,waitingNoiseUp   ; si se encuentra en estado de espera por tecla arriba no se atiende esta interrupción por posible rebote
        je endKeyInt

        mov state2,waitingNoiseDown ;pasar máquina de estados 2 a estado de espera por ruido al pulsar
        mov waitingNoise,0  ; limpiando contador para ruido
        ; en este punto es necesario apagar la interrupción de teclado 
        ; para evitar entradas mientras se mantiene el rebote de la tecla 

        endKeyInt:
            wrp IntA0,01100000b         ; ocw2 (fin de interrupción de tecla)
            iret
    KeyInt endp

    T5msint proc
        cmp state2,waitingNoiseDown   
        jne isWaitingNoiseUp                ; saltar si no se encuentra en estado de espera por tecla pulsada
            cmp waitingNoise,0              ; preguntar si el contador del ruido es 0
            jne incrementWaitingNoise       ; si es 0 hay que incrementarlo
                call keySweep               ; llamar a la rutina de barrido de teclado si han pasado 5ms
                mov state2,waitingNoiseUp   ; ir al estado de espera al soltar la tecla.
                jmp isDisplayRef            ; ir a refrescar el display
            incrementWaitingNoise:
                inc waitingNoise            ; incrementado contador para eliminar ruido de tecla
            jmp isDisplayRef                ; ir a refrescar el display

        isWaitingNoiseUp:
            cmp state2,waitingNoiseUp    
            jne isDisplayRef                ; saltar si no se encuentra en estado de espera al soltar tecla 
                inc waitingNoise            ; incrementado contador para eliminar ruido de tecla
                cmp waitingNoise,2          ; si el contador no es 20 indica que no han pasado 100 ms 
                jne isDisplayRef            ; si no han pasado 100ms ir a refrescar el display
                    mov state2,displayRef   ; si pasarom los 100ms la maquina de estados vuelve al estado displayRef
                    mov waitingNoise,0      ; limpiando contador para eliminar ruido
        
        isDisplayRef:
            cmp state,init                  ; si está en estado init el display no se refresca
            je endT5msint
                call RefDisplay             ; refrescar display
        endT5msint:
            wrp IntA0,01100001b ;ocw2
        iret 
    T5msint endp

    T500msInt proc near
        rdp al,PortB            ; cargando puerto b en "al" para modificar bits sin perder el esatdo actual.
        and al,10111111b        ; modificando el bit de la bocina.
        wrp PortB,al            ; apagando la bocina.
        wrp IntA1,11110100b     ;desactivando interrupción de 500ms
        wrp IntA0,01100010b     ;ocw2
        iret
    T500msInt endp

    T2sInt proc near
        rdp al,PortB            ; cargando puerto b en "al" para modificar bits sin perder el esatdo actual.
        and al,01111111b        ; modificando el bit de temporizadores.
        wrp PortB,al            ; apagando temporizadores 1 y 2.
        wrp IntA1,11111100b     ;desactivando interrupción de 2s
        mov state,init          ;cargando estado inicial.
        wrp IntA0,01100011b     ;ocw2
        iret
    T2sInt endp


end main