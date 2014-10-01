cdef class UI:
    '''
    The UI context for a glfw window.
    '''
    cdef Input new_input
    cdef bint should_redraw
    cdef public list elements
    cdef Vec2 window_size

    def __cinit__(self):
        self.elements = []
        self.new_input = Input()
        self.window_size = Vec2(0,0)

    def __init__(self):
        self.should_redraw = True

    def update_mouse(self,mx,my):
        if 0 <= mx <= self.window_size.x and 0 <= my <= self.window_size.y:
            self.new_input.dm.x,self.new_input.dm.y = mx-self.new_input.m.x,my-self.new_input.m.y
            self.new_input.m.x,self.new_input.m.y = mx,my


    def update_window(self,w,h):
        self.window_size.x,self.window_size.y = w,h
        self.should_redraw = True

    def input_key(self, key, scancode, action, mods):
        self.new_input.keys.append((key,scancode,action,mods))

    def input_char(self,c):
        self.new_input.chars.append(c)

    def input_button(self,button,action,mods):
        self.new_input.buttons.append((button,action,mods))

    def sync(self):
        cdef Menu e
        for e in self.elements:
            e.sync()

    cpdef handle_input(self):
        cdef Menu e
        if self.new_input:
            for e in self.elements:
                e.handle_input(self.new_input,True)
            self.new_input.purge()


    cpdef draw(self,context):
        global should_redraw
        cdef Menu e
        for e in self.elements:
            e.draw(context,FitBox(Vec2(0,0),self.window_size))
        should_redraw = True

    def update(self,context):
        global should_redraw
        self.handle_input()
        self.sync()
        if should_redraw:
            self.draw(context)


cdef class Menu:
    '''
    Menu is a movable object on the canvas that contains other elements.
    '''
    cdef public list elements
    cdef FitBox outline
    cdef public bint iconified
    cdef bytes label
    cdef long uid
    cdef Draggable handlebar, resize_corner
    cdef Vec2 top_left_padding

    def __cinit__(self,label,pos=(0,0),size=(200,100)):
        self.uid = id(self)
        self.label = label
        self.outline = FitBox(position=Vec2(*pos),size=Vec2(*size))
        self.top_left_padding = Vec2(20,0)
        self.elements = []


    def __init__(self,label,pos=(0,0),size=(200,100)):
        arrest_axis = 0
        self.handlebar = Draggable(Vec2(0,0),Vec2(20,0),self.outline.design_org,arrest_axis)
        self.resize_corner = Draggable(Vec2(-1,-1),Vec2(-19,-19),self.outline.design_size,arrest_axis)


    cpdef draw(self,context,parent_box):
        self.outline.compute(parent_box)
        context.save()
        self.draw_menu(context)

        self.handlebar.draw(context,self.outline)
        self.resize_corner.draw(context,self.outline)

        #lets manually resize
        self.outline.org += self.top_left_padding
        self.outline.size -= self.top_left_padding

        for e in self.elements:
            e.draw(context,self.outline)

        context.restore()

    cpdef draw_menu(self,context):
        context.beginPath()
        context.rect(*self.outline.rect)
        context.stroke()


    cpdef handle_input(self, Input new_input,bint m_close):
        self.handlebar.handle_input(new_input,True)
        self.resize_corner.handle_input(new_input,True)
        for e in self.elements:
            e.handle_input(new_input,True)

    cpdef sync(self):
        for e in self.elements:
            e.sync()

    property height:
        def __get__(self):
            return self.outline.size.y



cdef class StackBox:
    '''
    An element that contains stacks of other elements
    It will be scrollable if the content does not fit.
    '''
    cdef FitBox outline
    cdef Draggable scrollbar
    cdef Vec2 scrollstate
    cdef public list elements

    def __cinit__(self):
        self.outline = FitBox(Vec2(0,0),Vec2(0,0))
        self.scrollstate = Vec2(0,0)
        self.scrollbar = Draggable(Vec2(0,0),Vec2(0,0),self.scrollstate,arrest_axis=1)
    def __init__(self):
        self.elements = []

    cpdef sync(self):
        for e in self.elements:
            e.sync()


    cpdef handle_input(self,Input new_input,visible=True):
        cdef bint mouse_over_menue = 0 <= new_input.m.y-self.outline.org.y <= +self.outline.size.y
        for e in self.elements:
            e.handle_input(new_input, mouse_over_menue)
        # handle scrollbar interaction after menu items
        # so grabbing a slider does not trigger scrolling
        self.scrollbar.handle_input(new_input,True)



    cpdef draw(self,context,parent_size):
        self.outline.compute(parent_size)
        # dont show the stuff that does not fit.

        #display that we have scrollable content
        h = sum([e.height for e in self.elements])
        if h:
            scroll_factor = float(self.outline.size.y)/h
        else:
            scroll_factor = 2

        if scroll_factor < 1:
            self.outline.size.x -=20

        context.scissor(*self.outline.rect)


        #If the scollbar is not active make sure the content is scrolled away:
        if not self.scrollbar.selected:
            self.scrollstate.y = int(clamp(self.scrollstate.y,min(0,self.outline.size.y-h),0))

        self.scrollbar.draw(context,self.outline)

        self.outline.org.y += self.scrollstate.y
        for e in self.elements:
            e.draw(context,self.outline)
            self.outline.org.y+= e.height

        self.outline.org.y -= self.scrollstate.y
        self.outline.org.y -= h




cdef class Slider:
    cdef readonly bytes label
    cdef readonly long  uid
    cdef float minimum,maximum,step
    cdef public FitBox outline
    cdef bint selected
    cdef Vec2 slider_pos
    cdef Synced_Value sync_val

    def __cinit__(self,bytes attribute_name, object attribute_context,label = None, min = 0, max = 100, step = 1,setter= None,getter= None):
        self.uid = id(self)
        self.label = label or attribute_name
        self.sync_val = Synced_Value(attribute_name,attribute_context,getter,setter)
        self.minimum = min
        self.maximum = max
        self.step = step
        self.outline = FitBox(Vec2(0,0),Vec2(0,40)) # we only fix the height
        self.slider_pos = Vec2(0,20)
        self.selected = False

    def __init__(self,bytes attribute_name, object attribute_context,label = None, min = 0, max = 100, step = 1,setter= None,getter= None):
        pass


    cpdef sync(self):
        self.sync_val.sync()

    cpdef draw(self,context,FitBox parent):
        #update apperance:
        self.outline.compute(parent)

        # map slider value
        self.slider_pos.x = int( clampmap(self.sync_val.value,self.minimum,self.maximum,0,self.outline.size.x) )
        context.beginPath()
        context.rect(*self.outline.rect)
        context.stroke()
        #then transform locally and render the UI element
        context.save()
        context.translate(self.outline.org.x,self.outline.org.y)
        context.beginPath()
        context.textAlign(1<<4)
        context.text(20.0, 20.0, self.label)

        if self.selected:
            context.circle(self.slider_pos.x,self.slider_pos.y,14)
        else:
            context.circle(self.slider_pos.x,self.slider_pos.y,18)
        context.textAlign(1<<1 | 1<<4)
        context.text(self.slider_pos.x,self.slider_pos.y, str(self.sync_val.value))

        context.stroke()
        context.restore()

    cpdef handle_input(self,Input new_input,bint m_close):
        global should_redraw

        if self.selected and new_input.dm:
            self.sync_val.value = clampmap(new_input.m.x-self.outline.org.x,0,self.outline.size.x,self.minimum,self.maximum)
            should_redraw = True

        for b in new_input.buttons:
            if b[1] == 1 and m_close:
                if mouse_over_center(self.slider_pos+self.outline.org,self.height,self.height,new_input.m):
                    new_input.buttons.remove(b)
                    self.selected = True
                    should_redraw = True
            if self.selected and b[1] == 0:
                self.selected = False


    property height:
        def __get__(self):
            return self.outline.size.y


cdef class Draggable:
    '''
    A rectable that can be dragged.
    Does not move itself but the drag vector is added to 'value'
    '''
    cdef FitBox outline
    cdef Vec2 touch_point,drag_accumulator
    cdef bint selected
    cdef Vec2 value
    cdef int arrest_axis

    def __cinit__(self,Vec2 pos, Vec2 size, Vec2 value, arrest_axis = 0):
        self.outline = FitBox(pos,size)
        self.value = value
        self.selected = False
        self.touch_point = Vec2(0,0)
        self.drag_accumulator = Vec2(0,0)

        self.arrest_axis = arrest_axis

    def __init__(self,Vec2 pos, Vec2 size, Vec2 value, arrest_axis = 0):
        pass

    cdef draw(self,context, FitBox parent_size):
        self.outline.compute(parent_size)
        context.beginPath()
        context.rect(*self.outline.rect)
        context.stroke()

    cdef handle_input(self,Input new_input, bint visible):
        global should_redraw
        if self.selected and new_input.dm:
            self.value -= self.drag_accumulator
            self.drag_accumulator = new_input.m-self.touch_point
            if self.arrest_axis == 1:
                self.drag_accumulator.x = 0
            elif self.arrest_axis == 2:
                self.drag_accumulator.y = 0

            self.value += self.drag_accumulator

            should_redraw = True

        for b in new_input.buttons:
            if b[1] == 1 and visible:
                if self.outline.mouse_over(new_input.m):
                    self.selected = True
                    new_input.buttons.remove(b)
                    self.touch_point.x = new_input.m.x
                    self.touch_point.y = new_input.m.y
                    self.drag_accumulator = Vec2(0,0)
            if self.selected and b[1] == 0:
                self.selected = False

cdef class FitBox:
    '''
    A box that will fit itself into a context.
    Specified by rules for x and y respectivly:
        size 0 will span into parent context
        size negative will move Box origin to the other side
        position negative will align to the opposite side of context

    Its made of 4 Vec2
        "design_org" "design_size" define the rules for placement and size

        "org" and "size" are the computed results of the box
            fitted and translated by its parent context
    '''
    cdef Vec2 design_org,org,design_size,size

    def __cinit__(self,Vec2 position,Vec2 size):
        self.design_org = Vec2(position.x,position.y)
        self.design_size = Vec2(size.x,size.y)
        # The values below are just temporay
        # and will be overwritten by compute.
        self.org = Vec2(position.x,position.y)
        self.size = Vec2(size.x,size.y)

    def __init__(self,Vec2 position,Vec2 size):
        pass

    cdef compute(self,FitBox context):
        # all x
        if self.design_size.x > 0:
            # size is direcly specified
            self.size.x = self.design_size.x
        elif self.design_size.x < 0:
            # size is set but origin is mirrored
            self.size.x = - self.design_size.x
        else:
            # span parent context
            self.size.x = context.size.x
        #right align inside context
        if self.design_org.x < 0:
            self.org.x = context.size.x+self.design_org.x
        else:
            self.org.x = self.design_org.x
        # mir origin if design size is negative
        if self.design_size.x < 0:
            self.org.x += self.design_size.x
        # account for positon if span
        if self.design_size.x == 0:
            self.size.x -= self.org.x
        self.size.x = max(0,self.size.x)
        # finally translate into scene by parent org
        self.org.x +=context.org.x


        # copy replace for y
        if self.design_size.y > 0:
            # size is direcly specified
            self.size.y = self.design_size.y
        elif self.design_size.y < 0:
            # size is set but origin is mirrored
            self.size.y = - self.design_size.y
        else:
            # span parent context
            self.size.y = context.size.y
        if self.design_org.y < 0:
            self.org.y = context.size.y+self.design_org.y
        else:
            self.org.y = self.design_org.y
        # mir origin if design size is negative
        if self.design_size.y < 0:
            self.org.y += self.design_size.y
        # account for positon is span
        if self.design_size.y == 0:
            self.size.y -= self.org.y
        self.size.y = max(0,self.size.y)
        # finally translate into scene by parent org
        self.org.y +=context.org.y

    property rect:
        def __get__(self):
            return self.org.x,self.org.y,self.size.x,self.size.y

    property ellipse:
        def __get__(self):
            return self.org.x+self.size.x/2,self.org.y+self.size.y/2, self.size.x,self.size.y

    property center:
        def __get__(self):
            return self.org.x+self.size.x/2,self.org.y+self.size.y/2

    cdef bint mouse_over(self,Vec2 m):
        return self.org.x <= m.x <=self.org.x+self.size.x and self.org.y <= m.y <=self.org.y+self.size.y


cdef class Synced_Value:
    '''
    an element that has a synced value
    '''
    cdef object attribute_context
    cdef bytes attribute_name
    cdef object _value
    cdef object getter
    cdef object setter

    def __cinit__(self,bytes attribute_name, object attribute_context,getter=None,setter=None):
        self.attribute_context = attribute_context
        self.attribute_name = attribute_name
        self.getter = getter
        self.setter = setter

    def __init__(self,bytes attribute_name, object attribute_context,getter=None,setter=None):
        self.sync()


    cdef sync(self):

        if self.getter:
            val = self.getter()
            if val != self._value:
                self._value = val
                global should_redraw
                should_redraw = True

        elif self._value != self.attribute_context.__dict__[self.attribute_name]:
            self._value = self.attribute_context.__dict__[self.attribute_name]
            global should_redraw
            should_redraw = True


    property value:
        def __get__(self):
            return self._value
        def __set__(self,val):
            #conserve the type
            t = type(self._value)
            self._value = t(val)

            if self.setter:
                self.setter(self._value)

            self.attribute_context.__dict__[self.attribute_name] = self._value



cdef class Input:
    '''
    Holds accumulated user input collect during a frame.
    '''

    cdef public list keys,chars,buttons
    cdef Vec2 dm,m

    def __cinit__(self):
        self.keys = []
        self.buttons = []
        self.chars = []
        self.m = Vec2(0,0)
        self.dm = Vec2(0,0)

    def __init__(self):
        pass

    def __nonzero__(self):
        return bool(self.keys or self.chars or self.buttons or self.dm)

    def purge(self):
        self.keys = []
        self.buttons = []
        self.chars = []
        self.dm.x = 0
        self.dm.y = 0

cdef class Vec2:
    cdef public int x,y

    def __cinit__(self,int x, int y):
        self.x = x
        self.y = y

    def __init__(self,x,y):
        pass

    def __nonzero__(self):
        return bool(self.x or self.y)

    def __add__(self,Vec2 other):
        return Vec2(self.x+other.x,self.y+other.y)

    def __iadd__(self,Vec2 other):
        self.x +=other.x
        self.y += other.y
        return self

    def __sub__(self,Vec2 other):
        return Vec2(self.x-other.x,self.y-other.y)

    def __isub__(self,Vec2 other):
        self.x -=other.x
        self.y -= other.y
        return self

#cdef class Stack2(Vec2):
#    cdef list stack

#    def __cinit__(self,int x, int y):
#        self.x = x
#        self.y = y

#    def __init__(self,x,y):
#        self.stack = []

#    cpdef push(self):
#        self.stack.append(Vec2(self.x,self.y))

#    cpdef pop(self):
#        cdef Vec2 vec = self.stack.pop()
#        self.x = vec.x
#        self.y = vec.y



cdef inline float lmap(float value, float istart, float istop, float ostart, float ostop):
    '''
    linear mapping of val from space1 to space 2
    '''
    return ostart + (ostop - ostart) * ((value - istart) / (istop - istart))

cdef inline float clamp(float value, float minium, float maximum):
    return max(min(value,maximum),minium)

cdef inline float clampmap(float value, float istart, float istop, float ostart, float ostop):
    return clamp(lmap(value,istart,istop,ostart,ostop),ostart,ostop)

cdef inline bint mouse_over_center(Vec2 center, int w, int h, Vec2 m):
    return center.x-w/2 <= m.x <=center.x+w/2 and center.y-h/2 <= m.y <=center.y+h/2

